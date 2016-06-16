#!/usr/bin/env python3

import os
import sys
import time
import signal
import subprocess
import threading
import fnmatch


fuzzer_running=False

fuzzer_src='Fuzzer/'
libxml_src_dir='libxml_src/'
libxml_target_fuzzer='libxml_fuzzer.cc'

libxml_exec='libxml'
libxml_obj='libxml_fuzzer.o'
corpus='CORPUS'
llvm_prof_path='perf.llvm_prof'
exec_fuzzer='ASAN_OPTIONS=detect_odr_violation=0 ' + libxml_exec + \
        corpus + ' -close_fd_mask=2 -max_len=1024 '
perf_command='perf record -b -p'

pwd=os.getcwd()
prefix=os.path.join(pwd, 'inst')

cc="/home/alex/asap/build/bin/clang-3.7"
cov_flags="-fsanitize-coverage=edge,indirect-calls,8bit-counters"
basic_cflags=['-O2', '-fsanitize=address', cov_flags]
focused_cflags= basic_cflags + ['-fprofile-sample-use=' +
        os.path.join(os.getcwd(), llvm_prof_path), '-B/usr/bin/ld.gold',
        '-fsanitize=asap', '-mllvm', '-asap-cost-threshold=1000', '-flto']
focused_ldflags = ['-flto', '-B/usr/bin/ld.gold']
focused_ranlib = ['llvm-ranlib']
logfile='focusedfuzzing.log'
logfile_handler=1


def file_pattern(root, pattern):
    if not os.path.isdir(root):
        return []
    files =[]
    for file in os.listdir(root):
            if fnmatch.fnmatch(file, pattern):
                files.append(os.path.join(root, file))
    return files

build_fuzzer_cmd=['clang++', '-g'] + basic_cflags + ['-c', '-std=c++11',
    '-I' + prefix + '/include/libxml2', libxml_target_fuzzer]

link_fuzzer_cmd=['clang++', '-g', '-fsanitize=address', cov_flags, '-Wl,--whole-archive'] + \
        file_pattern(prefix + '/lib', '*.a') + ['-Wl,--whole-archive'] + \
        file_pattern(prefix + '/lib', '*.so') + ['-Wl,-no-whole-archive',
        'libFuzzer.a', '-lz', '-flto', '-B/usr/bin/ld.gold',
        libxml_obj]


def focused_build(cflags=basic_cflags, ldflags='', ranlib=''):
    os.chdir(libxml_src_dir)
    try:
        subprocess.check_call(['make', 'clean'], stdout=logfile_handler)
    except subprocess.CalledProcessError as e:
        print(e)

    subprocess.check_call(['./autogen.sh'], stdout=logfile_handler)

    if not os.path.isdir(prefix):
        os.mkdir(prefix)
    env_vars = dict(os.environ)
    env_vars['CC'] = cc
    configure_call='./configure --prefix=' + prefix
    print('[DEBUG] Start configure command:\n\t' + configure_call)
    subprocess.check_call(configure_call.split(), env=env_vars, stdout=logfile_handler)

    basic_fuzzer_command=['make',  '-j5', 'V=1', 'CC=' + cc + '',
            'CFLAGS=' + ' '.join(cflags)]

    if len(ldflags) > 0:
        basic_fuzzer_command.append('LDFLAGS=' + ' '.join(ldflags))

    if len(ranlib) > 0:
        basic_fuzzer_command.append('RANLIB=' + ' '.join(ranlib))
    print('[DEBUG] Running basic fuzzer command: \n\t' +
            str(' '.join(basic_fuzzer_command)))

    subprocess.check_call(basic_fuzzer_command, stdout=logfile_handler,
            stderr=subprocess.STDOUT)

    try:
        subprocess.check_call(['make', 'install'], stdout=logfile_handler)
    except subprocess.CalledProcessError as e:
        print(e)

    os.chdir('../')

def link_fuzzer(remove=True):
    if (not remove) and (not os.path.isfile('libFuzzer.a')):
        cmd = ['clang++', '-c', '-g', '-O2', '-std=c++11'] + \
                file_pattern('Fuzzer', '*.cpp') + ['-IFuzzer']
        print('[INFO] Running command\n\t' + ' '.join(cmd))
        subprocess.check_call(cmd, stdout=logfile_handler)

        cmd = ['ar', 'ruv', 'libFuzzer.a'] + file_pattern('.', 'Fuzzer*.o')
        print('[INFO] Running command\n\t' + ' '.join(cmd))
        subprocess.check_call(cmd, stdout=logfile_handler)

    print('[INFO] Running command \n\t' + ' '.join(build_fuzzer_cmd))
    subprocess.check_call(build_fuzzer_cmd, stdout=logfile_handler)
    print('[INFO] Running command \n\t' + ' '.join(link_fuzzer_cmd))
    subprocess.check_call(link_fuzzer_cmd, stdout=logfile_handler)
    subprocess.check_call(['mv', 'a.out', libxml_exec], stdout=logfile_handler)


def fuzzer_startup():
    if not os.path.isdir(os.path.join(os.getcwd(), libxml_src_dir)):
        #clone libxml
        subprocess.check_call(['git', 'clone',
        'git://git.gnome.org/libxml2', libxml_src_dir], stdout=logfile_handler)
        os.chdir(libxml_src_dir)
        subprocess.check_call(['git', 'checkout', '-b', 'old',
            '3a76bfeddeac9c331f761e45db6379c36c8876c3'], stdout=logfile_handler)
        os.chdir('../')
    if not os.path.exists(os.path.join(os.getcwd(),
        libxml_target_fuzzer)):
        print('[ERROR] Implement the target fuzzer source')
        return

    focused_build()

    #clone the fuzzer
    if not os.path.isdir(fuzzer_src):
        subprocess.check_call(['git', 'clone',
            'https://chromium.googlesource.com/chromium/llvm-project/llvm/lib/Fuzzer',
            fuzzer_src], stdout=logfile_handler)
    link_fuzzer(remove=False)
    if not os.path.isdir(corpus):
        os.mkdir(corpus)

def start_fuzzer_process():
    exec_path=os.path.join(pwd, libxml_exec)
    corpus_path=os.path.join(pwd, corpus)
    if not os.path.isfile(exec_path):
        print('[ERROR] The fuzzer executable could not be built')
        return 0

    env_vars = dict(os.environ)
    env_vars['ASAN_OPTIONS'] = 'detect_odr_violation=0'
    start_fuzzer_command = [exec_path, corpus_path,  '-close_fd_mask=2', '-max_len=5000']

    print('[DEBUG] Start libxml fuzzer command:\n\t' + ' '.join(start_fuzzer_command))
    libxml_proc = subprocess.Popen(start_fuzzer_command, env=env_vars, stdout=logfile_handler,
            stderr=subprocess.STDOUT)
    return libxml_proc


def main():
    fuzzer_startup()

    while True:
        libxml_proc_popen = start_fuzzer_process()
        libxml_proc_data = Process(libxml_proc_popen)
        libxml_proc_data.start_monitoring()
        print('[DEBUG] Started libxml fuzzer process with pid: [%d]' % (libxml_proc_popen.pid))


        time.sleep(5)
        perf_command = ['perf', 'record', '-b', '-p', str(libxml_proc_popen.pid)]
        print('[DEBUG] Start perf sampling command:\n\t' + ' '.join(perf_command))
        perf_proc = subprocess.Popen(perf_command, stdout=logfile_handler)
        time.sleep(20)

        os.kill(perf_proc.pid, signal.SIGINT)
        print('[DEBUG] Killed perf process with pid:[%d]' % (perf_proc.pid))
        time.sleep(5)

        #rebuild libxml
        perf_to_gcov_command = ['/usr/local/bin/create_llvm_prof', '--binary=' + libxml_exec,
                '--profile=perf.data', '--out=perf.llvm_prof']
        print('[DEBUG] Running perf to gcov command:\n\t' + ' '.join(perf_to_gcov_command))
        subprocess.check_call(perf_to_gcov_command, stdout=logfile_handler)

        focused_build(cflags=focused_cflags, ldflags=focused_ldflags, ranlib=focused_ranlib)
        link_fuzzer()

        libxml_proc_data.terminate()
        try:
            os.kill(libxml_proc_data.pid, signal.SIGINT)
        except ProcessLookupError:
            pass
        logfile_handler.flush()
        time.sleep(3)

class Process():
    def __init__(self, popen):
        self.pid = popen.pid
        self.should_run = True
        self.popen = popen
        self.crash_thread = threading.Thread(target=self.crash_detector)

    def crash_detector(self):
        while self.should_run:
            if self.popen.poll() != None:
                self.popen = start_fuzzer_process()
                if self.popen == 0:
                    continue
                self.pid = self.popen.pid
                self.running = True
                print('[DEBUG] Restarted libxml process with new pid [%s]' % self.pid)
            time.sleep(3)

    def start_monitoring(self):
        self.crash_thread.start()

    def terminate(self):
        self.should_run = False
        print('[DEBUG] The libxml process with pid [%s] exited' % (self.pid))
        self.crash_thread.join()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == 'clean':
        try:
            subprocess.check_call(['rm', '-r', 'CORPUS'] + \
                file_pattern('.', '*.o') + [libxml_exec, 'libFuzzer.a'])
        except subprocess.CalledProcessError as e:
            print(e)
    else:
        logfile_handler = open(logfile, 'a')
        main()

