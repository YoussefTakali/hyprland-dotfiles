"""Prepare the SDDM loading scene during installation."""
import argparse
from pathlib import Path
import re
import shutil


def patch_login_theme(main, fields):
    if 'property bool unifiedLoading:' not in main:
        anchor = '    focus: true\n'
        if anchor not in main:
            raise ValueError('Unrecognized SDDM Main.qml; loading hook was not installed.')
        loading = '''
    // One visual scene spans authentication and desktop startup.
    property bool unifiedLoading: false
    function startLoading() { player.pause(); unifiedLoading = true; }
    function stopLoading() { unifiedLoading = false; player.play(); }
    JakeLoadingScene {
        anchors.fill: parent
        z: 1000
        visible: root.unifiedLoading
        animated: root.unifiedLoading
        MouseArea { anchors.fill: parent }
    }
'''
        main = main.replace(anchor, anchor + loading, 1)
    if 'root.startLoading()' not in fields:
        anchor = '        sddm.login(targetUser, password.text, sessionSelect.selectedSession)'
        failed = '        function onLoginFailed() {\n'
        if anchor not in fields or failed not in fields:
            raise ValueError('Unrecognized SDDM Input.qml; loading hook was not installed.')
        fields = fields.replace('    function triggerLogin() {\n',
                                '    function triggerLogin() {\n        if (root.unifiedLoading) return\n', 1)
        fields = fields.replace(anchor, '        root.startLoading()\n' + anchor, 1)
        fields = fields.replace(failed, failed + '            root.stopLoading()\n', 1)
    return main, fields


def prepare_theme(theme):
    """Install the loading scene independently of an exported transition frame."""
    scene = Path(__file__).resolve().parents[2] / 'config/quickshell/login-splash'
    components = theme / 'Components'
    poster = theme / 'Backgrounds/jake_the_dog.png'
    if not poster.is_file():
        raise RuntimeError('SDDM Astronaut is missing the default Jake poster.')
    main = theme / 'Main.qml'
    fields = components / 'Input.qml'
    main_text, fields_text = patch_login_theme(main.read_text(), fields.read_text())
    main.write_text(main_text)
    fields.write_text(fields_text)
    shutil.copyfile(scene / 'JakeLoadingScene.qml', components / 'JakeLoadingScene.qml')
    shutil.copyfile(poster, components / 'jake.png')
    metadata = theme / 'metadata.desktop'
    metadata.write_text(re.sub(r'^ConfigFile=.*$', 'ConfigFile=Themes/jake_the_dog.conf',
                               metadata.read_text(), flags=re.M))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('theme', type=Path)
    prepare_theme(parser.parse_args().theme)
