#!/usr/bin/env python3

import os
import sys
import time
import signal
import subprocess
import argparse
import threading
import fnmatch


###### Default running params
default_setup = {'corpus':'CORPUS', 'sampling_time':20, 'max_len':2000, 'seed':0, 'asap_cost_threshold':1000}
running_setup = default_setup
real_act = default_setup['asap_cost_threshold']


##### Commands and configuration parameters
fuzzer_running=False

fuzzer_src='Fuzzer/'
libxml_src_dir='libxml_src/'
libxml_target_fuzzer='libxml_fuzzer.cc'

libxml_exec='libxml'
libxml_obj='libxml_fuzzer.o'
llvm_prof_path='perf.llvm_prof'

pwd=os.getcwd()
prefix=os.path.join(pwd, 'inst')

cc="/home/alex/asap/build/bin/clang-3.7 -g"
cov_flags="-fsanitize-coverage=edge,indirect-calls"
basic_cflags=['-O2', '-fsanitize=address', cov_flags]
focused_cflags= basic_cflags + ['-fprofile-sample-use=' +
        os.path.join(os.getcwd(), llvm_prof_path), '-B/usr/bin/ld.gold',
        '-fsanitize=asap', '-mllvm', '-asap-cost-threshold=' + str(default_setup['asap_cost_threshold'])]
focused_ldflags = ['-B/usr/bin/ld.gold']
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
        file_pattern(os.path.join(prefix, 'lib'), '*.a') + ['-Wl,-no-whole-archive',
        'libFuzzer.a', '-lz', '-B/usr/bin/ld.gold',
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
    configure_call= ['./configure', '--prefix=' + prefix, '--enable-option-checking',
            '--disable-shared', '--disable-ipv6',
            '--without-c14n', '--without-catalog', '--without-debug', '--without-docbook', '--without-ftp', '--without-http',
            '--without-legacy', '--without-output', '--without-pattern', '--without-push', '--without-python',
            '--without-reader', '--without-readline', '--without-regexps', '--without-sax1', '--without-schemas',
            '--without-schematron', '--without-threads', '--without-valid', '--without-writer', '--without-xinclude',
            '--without-xpath', '--without-xptr', '--without-zlib', '--without-lzma']
    print('[DEBUG] Start configure command:\n\t' + ' '.join(configure_call))
    subprocess.check_call(configure_call, env=env_vars, stdout=logfile_handler)

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
    if not os.path.isdir(running_setup['corpus']):
        os.mkdir(running_setup['corpus'])

def start_fuzzer_process():
    exec_path=os.path.join(pwd, libxml_exec)
    corpus_path=os.path.join(pwd, running_setup['corpus'])
    if not os.path.isfile(exec_path):
        print('[ERROR] The fuzzer executable could not be built')
        return 0

    env_vars = dict(os.environ)
    env_vars['ASAN_OPTIONS'] = '''poison_array_cookie=false:
        poison_partial=false:
        atexit=true:
        print_stats=true:
        malloc_context_size=0:
        detect_odr_violation=0:
        poison_heap=false:
        quarantine_size_mb=0:
        report_globals=0:
        coverage=1:
        html_cov_report=1'''
    start_fuzzer_command = ['taskset', '-c', '3', exec_path, corpus_path,  '-close_fd_mask=2',
            '-max_len=' + str(running_setup['max_len']), '-seed=' + str(running_setup['seed']), '-print_final_stats=1', '-runs=500000']

    print('[DEBUG] Start libxml fuzzer command:\n\t' + ' '.join(start_fuzzer_command) +
            '\n\tasap-cost-threshold:[%d]' % real_act, file=logfile_handler)
    logfile_handler.flush()

    print('[DEBUG] Start libxml fuzzer command:\n\t' + ' '.join(start_fuzzer_command) +
            '\n\tasap-cost-threshold:[%d]'% real_act)

    libxml_proc = subprocess.Popen(start_fuzzer_command, env=env_vars, stdout=logfile_handler,
            stderr=subprocess.STDOUT)
    return libxml_proc

def clear_dir(name):
    filelist = [ f for f in os.listdir(name) ]
    for f in filelist:
        os.remove(f)

def main(clean=False, full=False):

    if full:
        fuzzer_startup()
        return

    if clean:
        fuzzer_startup()

    cycles = 0
    while True:
        corpus_path=os.path.join(pwd, running_setup['corpus'])
        #clear_dir(corpus_path)

        libxml_proc_popen = start_fuzzer_process()
        libxml_proc_data = Process(libxml_proc_popen)
        libxml_proc_data.start_monitoring()
        print('[DEBUG] Started libxml fuzzer process with pid: [%d]' % (libxml_proc_popen.pid))

        cycles += 1
        time.sleep(2)
        try:
            perf_command = ['perf', 'record', '-g', '-b', '-p', str(libxml_proc_popen.pid)]
            print('[DEBUG] Start perf sampling command:\n\t' + ' '.join(perf_command))
            perf_proc = subprocess.Popen(perf_command, stdout=logfile_handler)
            time.sleep(running_setup['sampling_time'])

            os.kill(perf_proc.pid, signal.SIGINT)
            print('[DEBUG] Killed perf process with pid:[%d]' % (perf_proc.pid))
            time.sleep(5)

            #rebuild libxml
            perf_to_gcov_command = ['/usr/local/bin/create_llvm_prof', '--binary=' + libxml_exec,
                    '--profile=perf.data', '--out=perf.llvm_prof']
            print('[DEBUG] Running perf to gcov command:\n\t' + ' '.join(perf_to_gcov_command))
            subprocess.check_call(perf_to_gcov_command, stdout=logfile_handler)
        except Exception as e:
            fuzzer_startup()

        focused_build(cflags=focused_cflags, ldflags=focused_ldflags, ranlib=focused_ranlib)
        link_fuzzer()

        libxml_proc_data.terminate()
        try:
            os.kill(libxml_proc_data.pid, signal.SIGINT)
        except ProcessLookupError:
            pass
        logfile_handler.flush()
        time.sleep(1)
        real_act = running_setup['asap_cost_threshold']
        os.rename('perf.data', 'perf.data' + str(cycles))

        if cycles == 2:
            break

class Process():
    def __init__(self, popen):
        self.pid = popen.pid
        self.should_run = True
        self.popen = popen
        self.original_popen = popen
        self.crash_thread = threading.Thread(target=self.crash_detector)

    def crash_detector(self):
        while self.should_run:
            if self.popen.poll() != None:
                self.popen = start_fuzzer_process()
                self.pid = self.popen.pid
                self.original_popen.pid = self.pid
                self.running = True
                print('[DEBUG] Restarted libxml process with new pid [%s]' % self.pid)
            time.sleep(3)

    def start_monitoring(self):
        self.crash_thread.start()

    def terminate(self):
        self.should_run = False
        print('[DEBUG] The libxml process with pid [%s] exited' % (self.pid))
        self.crash_thread.join()

def get_arg(param):
    if param.count('=')  != 1:
        return ''
    return param.split('=')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-command', required=True)
    parser.add_argument('-corpus', required=True)
    parser.add_argument('-sampling-time', required=True)
    parser.add_argument('-max-len', required=True)
    parser.add_argument('-seed', required=True)
    parser.add_argument('-asap-cost-threshold', required=True)
    parser.add_argument('-clean', action='store_true')
    parser.add_argument('-full', action='store_true')
    res = vars(parser.parse_args(sys.argv[1:]))

    print(res)
    if res['command'] == 'clean':
        try:
            subprocess.check_call(['rm', '-r', 'CORPUS'] + \
                    file_pattern('.', '*.o') + [libxml_exec, 'libFuzzer.a'])
        except subprocess.CalledProcessError as e:
            print(e)
        exit()

    running_setup['corpus'] = res['corpus']
    running_setup['sampling_time'] = int(res['sampling_time'])
    running_setup['max_len'] = int(res['max_len'])
    running_setup['seed'] = int(res['seed'])
    running_setup['asap_cost_threshold'] = int(res['asap_cost_threshold'])

    focused_cflags= basic_cflags + ['-fprofile-sample-use=' +
        os.path.join(os.getcwd(), llvm_prof_path), '-B/usr/bin/ld.gold',
        '-fsanitize=asap', '-mllvm', '-asap-cost-threshold=' + str(running_setup['asap_cost_threshold'])]


    logfile_handler = open(logfile, 'a')
    print(('[INFO] Running focused fuzzer with the following parameters:\n\t' +
            'corpus path:[%s] ' + 'sampling_time:[%d] ' + 'max_len:[%d] ' +
            'seed:[%d] asap-cost-threshold:[%d]') %
            (running_setup['corpus'], running_setup['sampling_time'],
                running_setup['max_len'], running_setup['seed'], running_setup['asap_cost_threshold']),
            file=logfile_handler)
    logfile_handler.flush()

    main(clean=res['clean'], full=res['full'])
