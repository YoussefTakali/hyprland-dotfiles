#!/usr/bin/env python3
"""Verify the native trial gates, one-shot behavior and packaged fallback."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("trial_launcher", REPO/"config/hypr/scripts/StartHyprland.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)
spec = importlib.util.spec_from_file_location("session_install", REPO/"installer/install-session.py")
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)


class TrialTests(unittest.TestCase):
    def make(self, home):
        library = home/"private/libaquamarine.so.0.16.0"
        library.parent.mkdir()
        library.write_bytes(b"candidate")
        manifest = home/"manifest.json"
        manifest.write_text(json.dumps({"packages":["aq-1","utils-1","hypr-1"],"library":str(library),
                                        "sha256":hashlib.sha256(library.read_bytes()).hexdigest(),"trial_id":"test-trial"}))
        return library, manifest

    def test_valid_candidate_is_private_and_does_not_reuse_stale_initial_modes(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp);library,manifest=self.make(home)
            with patch.object(launcher.Path,'home',return_value=home), \
                 patch.object(launcher.subprocess,'check_output',return_value='aq-1\nutils-1\nhypr-1\n'), \
                 patch.object(launcher.time,'monotonic',return_value=100):
                env=launcher.native_environment(manifest,{'LD_LIBRARY_PATH':'/custom'})
            self.assertEqual(env['LD_LIBRARY_PATH'],str(library.parent)+':/custom')
            self.assertNotIn('AQ_DRM_CACHED_MODES_DEADLINE',env)
            self.assertTrue((home/'.local/state/session-startup/native-trial.json').exists())

    def test_changed_packages_never_activate(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);_,manifest=self.make(home)
            with patch.object(launcher.Path,'home',return_value=home), patch.object(launcher.subprocess,'check_output',return_value='changed\n'):
                with self.assertRaisesRegex(ValueError,'versions changed'):launcher.native_environment(manifest,{})
            self.assertFalse((home/'.local/state/session-startup/native-trial.json').exists())

    def test_changed_library_checksum_never_activates(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);library,manifest=self.make(home);library.write_bytes(b'changed')
            with patch.object(launcher.Path,'home',return_value=home), patch.object(launcher.subprocess,'check_output',return_value='aq-1\nutils-1\nhypr-1\n'):
                with self.assertRaisesRegex(ValueError,'checksum changed'):launcher.native_environment(manifest,{})

    def test_changed_kernel_never_activates(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);_,manifest=self.make(home);data=json.loads(manifest.read_text());data['kernel']='different-kernel';manifest.write_text(json.dumps(data))
            with patch.object(launcher.Path,'home',return_value=home), patch.object(launcher.subprocess,'check_output',return_value='aq-1\nutils-1\nhypr-1\n'):
                with self.assertRaisesRegex(ValueError,'kernel changed'):launcher.native_environment(manifest,{})

    def test_next_login_is_packaged_even_after_a_successful_trial(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);_,manifest=self.make(home)
            with patch.object(launcher.Path,'home',return_value=home), patch.object(launcher.subprocess,'check_output',return_value='aq-1\nutils-1\nhypr-1\n'):
                launcher.native_environment(manifest,{})
                (home/'.local/state/session-startup/native-trial.json').unlink()
                with self.assertRaisesRegex(ValueError,'one-shot'):launcher.native_environment(manifest,{})

    def test_unconfirmed_previous_trial_stays_disabled(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);_,manifest=self.make(home)
            with patch.object(launcher.Path,'home',return_value=home), patch.object(launcher.subprocess,'check_output',return_value='aq-1\nutils-1\nhypr-1\n'):
                launcher.native_environment(manifest,{})
                with self.assertRaisesRegex(ValueError,'previous native login'):launcher.native_environment(manifest,{})

    def test_early_failure_retries_packaged_exactly_once_with_clean_environment(self):
        for code in (0,1,127):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as tmp:
                state=Path(tmp);(state/'native-trial.json').touch()
                args=['/usr/bin/start-hyprland','--no-nixgl']
                child=unittest.mock.Mock();child.wait.return_value=code
                with patch.object(launcher.subprocess,'Popen',return_value=child), \
                     patch.object(launcher.os,'execve',side_effect=RuntimeError('packaged-exec')) as execute:
                    with self.assertRaisesRegex(RuntimeError,'packaged-exec'):
                        launcher.run_trial(args,{'LD_LIBRARY_PATH':'candidate'},{'PATH':'/usr/bin'},state)
                self.assertEqual(execute.call_count,1)
                self.assertEqual(execute.call_args.args,('/usr/bin/start-hyprland',args,{'PATH':'/usr/bin'}))

    def test_completed_session_and_explicit_interruption_do_not_relaunch(self):
        with tempfile.TemporaryDirectory() as tmp:
            state=Path(tmp);child=unittest.mock.Mock();child.wait.return_value=0
            with patch.object(launcher.subprocess,'Popen',return_value=child), patch.object(launcher.os,'execve') as execute:
                self.assertEqual(launcher.run_trial(['start'],{}, {},state),0)
            execute.assert_not_called()
            marker=state/'native-trial.json';marker.touch()
            self.assertFalse(launcher.trial_failed_before_startup(1,marker,interrupted=True))
            self.assertFalse(launcher.trial_failed_before_startup(0,marker,elapsed=60))
            marker.unlink()
            self.assertFalse(launcher.trial_failed_before_startup(1, marker, elapsed=60))

    def test_packaged_fallback_does_not_inherit_native_loader_settings(self):
        env=launcher.packaged_environment({'PATH':'/usr/bin','LD_LIBRARY_PATH':'candidate:/custom',
            'HYPRLAND_NATIVE_ACTIVE':'1','HYPRLAND_NATIVE_PREVIOUS_LD_LIBRARY_PATH':'/custom','AQ_DRM_CACHED_MODES_DEADLINE':'103'})
        self.assertEqual(env,{'PATH':'/usr/bin','LD_LIBRARY_PATH':'/custom'})

    def test_normal_launcher_ignores_an_existing_candidate_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);manifest=home/'.config/hypr/native-startup.json';manifest.parent.mkdir(parents=True);manifest.write_text('{}')
            with patch.object(launcher.Path,'home',return_value=home), patch.object(sys,'argv',['launcher']), \
                 patch.object(launcher,'native_environment') as native, patch.object(launcher,'warm_wallpaper_cache'), \
                 patch.object(launcher.os,'execve') as execute:
                launcher.main()
            native.assert_not_called()
            self.assertNotIn('HYPRLAND_NATIVE_ACTIVE',execute.call_args.args[2])

    def test_trial_session_does_not_change_the_stable_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);session.install(root,trial=True)
            stable=(root/'usr/local/libexec/hyprland-dotfiles-session').read_text()
            trial=(root/'usr/local/libexec/hyprland-dotfiles-trial-session').read_text()
            self.assertNotIn('--native-trial',stable)
            self.assertIn('--native-trial',trial)
            self.assertIn('measurement-origin post-profile',stable)


if __name__=='__main__':unittest.main()
