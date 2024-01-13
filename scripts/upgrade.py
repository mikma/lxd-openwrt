#!/usr/bin/python3

import re
import sys
import time
import pylxd
from pylxd import Client

class ExecuteError(RuntimeError):
        def __init__(self, command, exit_code):
                self.command = command
                self.exit_code = exit_code

        def __str__(self):
                return 'Command "%s" exit code %d' % (' '.join(self.command), self.exit_code)

def find_source_image(client, image):
        try:
                client.images.get_by_alias(image)
                return {'type': 'image', 'alias': image}
        except pylxd.exceptions.NotFound as e:
                if len(image) >= 12:
                        client.images.get(image)
                        return {'type': 'image', 'fingerprint': image}
                else:
                        raise

def copy_config(old, new):
        new.devices = old.devices
        new.description = old.description
        new_config = new.config

        for key, value in old.config.items():
                if key.endswith("hwaddr"):
                        new_config[key] = value

#        for key, value in new_config.items():
#                print("%s %s" % (key, value))

        new.config = new_config

def log_stdout(message):
        print(message, end='', flush=True)

def log_stderr(message):
        print(message, end='', file=sys.stderr, flush=True)

class Container:
        def __init__(self, container):
                self.container = container

        def __getattr__(self, name):
                return self.container.__getattribute__(name)

        def __setattr__(self, name, value):
                if name not in ('container'):
                        self.container.__setattr__(name, value)
                else:
                        super(Container, self).__setattr__(name, value)

        def execute_with_output(self, command, *args, **kwargs):
                extra_args={}
                if 'stderr_handler' not in kwargs:
                        extra_args['stderr_handler'] = log_stderr
                (exit_code, stdout, stderr) = self.container.execute(command, *args, **kwargs, **extra_args)
                if exit_code != 0:
                        raise ExecuteError(command, exit_code)
                return stdout

        def execute(self, command, *args, **kwargs):
                extra_args={}
                if 'stdout_handler' not in kwargs:
                        extra_args['stdout_handler'] = log_stdout
                self.execute_with_output(command, *args, **kwargs, **extra_args)

        def execute_retry(self, command, retries, *args, **kwargs):
                for i in range(retries + 1):
                        try:
                                self.execute(command, *args, **kwargs)
                        except ExecuteError as e:
                                if i == retries:
                                        raise
                                continue
                        return
                raise NotImplementedError()

        def ping(self, dest):
                self.execute_retry(['ping', '-c', '1', '-q', dest], 2,
                                   stdout_handler=None)

        def sysupgrade_backup(self, ):
                return self.execute_with_output(['sysupgrade', '-b', '-'],
                                                encoding='raw', decode=False)

        def sysupgrade_restore(self, data):
                backup_file = '/tmp/lxd-upgrade.tar.gz'
                self.files.put(backup_file, data)
                self.execute(['sysupgrade', '-r', backup_file])

        def opkg_list_installed(self, ):
                return self.execute_with_output(['opkg', 'list-installed'])

        def opkg_update(self):
                print("Update")
                self.execute(['opkg', 'update'])

        def opkg_install(self, packages):
                print("Installing %s" % packages)
                self.execute(['opkg', 'install'] + packages)

        def opkg_remove(self, packages):
                print("Removing %s" % packages)
                self.execute(['opkg', 'remove'] + packages)

        def _package_set_from_str(self, s):
                print("_package_set_from_str ", type(s))
                old_list = s.split('\n')
                old_packages = []
                pat = re.compile(r'([\w\.\-]*?)[0-9][0-9a-f\.\-]*')
                i = 1
                for l in old_list:
                        i = i + 1
                        res = l.split(' ')
                        if len(res) == 3:
                                (name, _, version) = res
                                if name.startswith('lib'):
                                        m = pat.match(name)
                                        if m:
                                                name = m[1]
                                old_packages.append(name)
                return frozenset(old_packages)

        def package_set(self):
                return self._package_set_from_str(self.opkg_list_installed())

        def orig_package_set(self):
                return self._package_set_from_str(self.container.files.get('/etc/openwrt_manifest').decode('ascii'))

        def save_orig_package_set(self):
                self.execute(['sh', '-c', 'opkg list-installed > tee /etc/openwrt_manifest'])


def usage(argv):
        print("Usage:", argv[0], "<old container> <new container> <image>")
        exit(1)

def main(argv):
        is_allow_existing = False

        if len(argv) == 4:
                pos = 1
        else:
                usage(argv)

        old_name = argv[pos]; pos=pos+1
        new_name = argv[pos]; pos=pos+1
        new_image = argv[pos]; pos=pos+1
        client = Client()

        old = Container(client.containers.get(old_name))

        if old.status == 'Stopped':
                print("Start", old_name)
                old.start(wait=True)

        new_source = find_source_image(client, new_image)
        new_config = {'name': new_name, 'source': new_source, 'profiles': old.profiles}

        if is_allow_existing and client.containers.exists(new_name):
                new = Container(client.containers.get(new_name))
        else:
                print("Create", new_name, new_config)
                new = Container(client.containers.create(new_config, wait=True))

        if new.status == 'Stopped':
                print("Start", new_name)
                new.start(wait=True)

                print("Ping downloads.openwrt.org")
                new.ping('downloads.openwrt.org')

                print("Update package list")
                new.opkg_update()

        print("Build /etc/openwrt_manifest")
        new.save_orig_package_set()

        orig_set = old.orig_package_set()
        old_set = old.package_set()
        new_set = new.package_set()
        del_set = orig_set.difference(old_set)
        add_set = old_set.difference(orig_set)
        del_packages = list(del_set)
        add_packages = list(add_set.difference(['iw']))

        if len(del_packages) > 0:
                print("Remove", del_packages)
                new.opkg_remove(del_packages)
        else:
                print("No packages uninstalled")

        if len(add_packages) > 0:
                print("Install", add_packages)
                new.opkg_install(add_packages)
        else:
                print("No packages installed")

        print("Backup", old_name)
        backup_data = old.sysupgrade_backup()

        print("Restore", new_name)
        new.sysupgrade_restore(backup_data)

        print("Stop", old_name)
        old.stop(wait=True)

        print("Stop", new_name)
        new.stop(wait=True)

        print("Copy config")
        copy_config(old, new)
        new.save()

        print("Wait 2s")
        time.sleep(2)

        print("Start", new_name)
        new.start(wait=True)
        print("Finished")

if __name__ == '__main__':
        main(sys.argv)
