import os

from .base import Dependency, ReleaseDownload, Builder
from kiwixbuild.utils import Remotefile, add_execution_right, run_command

pj = os.path.join

class android_ndk(Dependency):
    dont_skip = True
    neutral = False
    name = 'android-ndk'
    gccver = '4.9.x'
    api = '24'

    class Source(ReleaseDownload):
        archive = Remotefile('android-ndk-r21e-linux-x86_64.zip',
                             'ad7ce5467e18d40050dc51b8e7affc3e635c85bd8c59be62de32352328ed467e',
                             'https://dl.google.com/android/repository/android-ndk-r21e-linux-x86_64.zip')

        @property
        def source_dir(self):
            return self.target.full_name()


    class Builder(Builder):
        @property
        def install_path(self):
            return self.build_path

        @property
        def api(self):
            return self.target.api

        @property
        def platform(self):
            return 'android-'+self.api

        @property
        def arch(self):
            return self.buildEnv.platformInfo.arch

        @property
        def arch_full(self):
            return self.buildEnv.platformInfo.arch_full

        def _build_platform(self, context):
            context.try_skip(self.build_path)
            script = pj(self.source_path, 'build/tools/make_standalone_toolchain.py')
            add_execution_right(script)
            command = '{script} --arch={arch} --api={api} --install-dir={install_dir} --force'
            command = command.format(
                script=script,
                arch=self.arch,
                api=self.api,
                install_dir=self.install_path
            )
            env = self.buildEnv.get_env(cross_comp_flags=False, cross_compilers=False, cross_path=False)
            run_command(command, self.build_path, context, env=env)

        def _fix_permission_right(self, context):
            context.try_skip(self.build_path)
            bin_dirs = [pj(self.install_path, 'bin'),
                        pj(self.install_path, self.arch_full, 'bin'),
                        pj(self.install_path, 'libexec', 'gcc', self.arch_full, self.target.gccver)
                       ]
            for root, dirs, files in os.walk(self.install_path):
                if not root in bin_dirs:
                    continue

                for file_ in files:
                    file_path = pj(root, file_)
                    if os.path.islink(file_path):
                        continue
                    add_execution_right(file_path)

        def build(self):
            self.command('build_platform', self._build_platform)
            self.command('fix_permission_right', self._fix_permission_right)

