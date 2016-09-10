#!/usr/bin/env python3

# pylint: disable=line-too-long
# pylint: disable=invalid-name
# pylint: disable=bad-continuation
# pylint: disable=missing-docstring

import logging
import os
import sys
import time
import signal
import subprocess
import argparse
import threading
import fnmatch


###### Default running params
default_setup = {'corpus':'CORPUS', 'sampling_time':20, 'max_len':2000, 'seed':0, 'max_total_time':20, 'asap_cost_threshold':1000, 'sw':'libxml'}
running_setup = default_setup


##### Commands and configuration parameters
fuzzer_running = False

fuzzer_src = 'Fuzzer'
src_dir = {'libxml':'libxml_src', 'pcre':'pcre_src', 'http_parser':'http_parser_src'}

exec_file = {'libxml':'libxml', 'pcre':'pcre', 'http_parser':'http_parser'}
source_file = {'libxml':'libxml_fuzzer.cc', 'pcre':'pcre_fuzzer.cc', 'http_parser':'http_parser.cc'}
obj_file = {'libxml':'libxml_fuzzer.o', 'pcre':'pcre_fuzzer.o', 'http_parser':'http_parser.o'}
llvm_prof_path = 'perf.llvm_prof'

global prefix

cov_flags = None
basic_cflags = None
focused_cflags = None
focused_ldflags = None
focused_ranlib = None

build_fuzzer_cmd = None

logfile = 'focusedfuzzing.log'
NUM_JOBS = os.cpu_count() or 5

def which(program):
    """Finds `program` in $PATH."""
    return subprocess.check_output(['which', program]).strip()

def file_pattern(root, pattern):
    if not os.path.isdir(root):
        return []
    files = []
    for file in os.listdir(root):
        if fnmatch.fnmatch(file, pattern):
            files.append(os.path.join(root, file))
    return files

def focused_build(cflags=None, ldflags=None, ranlib=None):
    os.chdir(src_dir[running_setup['sw']])
    try:
        subprocess.check_call(['make', 'clean'], stdout=logfile_handler)
    except subprocess.CalledProcessError:
        logging.exception('Exception during focused_build:')

    if not os.path.isfile('configure'):
        subprocess.check_call(['./autogen.sh'], stdout=logfile_handler)

    if not os.path.isdir(prefix):
        os.mkdir(prefix)
    env_vars = dict(os.environ)
    env_vars['PATH'] = '/home/alex/asap/build/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games'
    env_vars['CC'] = which('clang') + str.encode(' -fsanitize=address ' + cov_flags)
    env_vars['CXX'] = which('clang++')
    configure_call = {'libxml': ['./configure', '--prefix=' + prefix, '--enable-option-checking',
            '--disable-shared', '--disable-ipv6',
            '--without-c14n', '--without-catalog', '--without-debug', '--without-docbook', '--without-ftp', '--without-http',
            '--without-legacy', '--without-output', '--without-pattern', '--without-push', '--without-python',
            '--without-reader', '--without-readline', '--without-regexps', '--without-sax1', '--without-schemas',
            '--without-schematron', '--without-threads', '--without-valid', '--without-writer', '--without-xinclude',
            '--without-xpath', '--without-xptr', '--without-zlib', '--without-lzma'],
            'pcre':['./configure', '--prefix=' + prefix, '--disable-shared'],
            'http_parser':[]}

    logging.debug('Start configure command:\n\t%s', ' '.join(configure_call[running_setup['sw']]))
    if len(configure_call[running_setup['sw']]):
        subprocess.check_call(configure_call[running_setup['sw']], env=env_vars, stdout=logfile_handler)

    if cflags is None:
        cflags = basic_cflags
    basic_fuzzer_command = ['make', '-j', str(NUM_JOBS), 'V=1', 'CC=clang', 'CFLAGS=' + ' '.join(cflags)]

    if ldflags:
        basic_fuzzer_command.append('LDFLAGS=' + ' '.join(ldflags))

    if ranlib:
        basic_fuzzer_command.append('RANLIB=' + ' '.join(ranlib))
    logging.debug('Running basic fuzzer command:\n\t%s',
            ' '.join(basic_fuzzer_command))

    subprocess.check_call(basic_fuzzer_command, stdout=logfile_handler,
            stderr=subprocess.STDOUT)

    try:
        env_vars = dict(os.environ)
        env_vars['PREFIX'] = prefix
        subprocess.check_call(['make', 'install'], env=env_vars, stdout=logfile_handler)
    except subprocess.CalledProcessError:
        logging.exception("Exception while running `make install`:")

    os.chdir('../')

def update_link_fuzzer_command():
    libs = file_pattern(os.path.join(prefix, 'lib'), '*.a')
    libs_str = ' '.join(['-Wl,--whole-archive ' + l for l in libs])
    if running_setup['sw'] == 'http_parser':
        libs_str = os.path.join(src_dir['http_parser'], 'http_parser.o')

    return ['clang++', '-B/usr/bin/ld.gold', '-fsanitize=address', cov_flags,
            '-o', exec_file[running_setup['sw']], obj_file[running_setup['sw']]] +\
                    libs_str.split() + ['-Wl,--no-whole-archive', 'libFuzzer.a']


def link_fuzzer(remove=True):
    if (not remove) and (not os.path.isfile('libFuzzer.a')):
        cmd = ['clang++', '-c', '-g', '-O2', '-std=c++11'] + \
                file_pattern('Fuzzer', '*.cpp') + ['-IFuzzer']
        logging.info('Running command\n\t%s', ' '.join(cmd))
        subprocess.check_call(cmd, stdout=logfile_handler)

        cmd = ['ar', 'ruv', 'libFuzzer.a'] + file_pattern('.', 'Fuzzer*.o')
        logging.info('Running command\n\t%s', ' '.join(cmd))
        subprocess.check_call(cmd, stdout=logfile_handler)

    logging.info('Running command \n\t%s', ' '.join(build_fuzzer_cmd))
    subprocess.check_call(build_fuzzer_cmd, stdout=logfile_handler)

    link_fuzzer_cmd = update_link_fuzzer_command() #needs to be done in case of clean build
    logging.info('Running command \n\t%s', ' '.join(link_fuzzer_cmd))
    subprocess.check_call(link_fuzzer_cmd, stdout=logfile_handler)

def fuzzer_startup():
    if not os.path.isdir(os.path.join(os.getcwd(), src_dir[running_setup['sw']])):
        #clone sw
        download = {'libxml':['git', 'clone', 'git://git.gnome.org/libxml2', src_dir[running_setup['sw']]],
                'pcre':['wget', 'ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre2-10.20.tar.gz'],
                'http_parser':['git', 'clone', 'https://github.com/nodejs/http-parser.git', src_dir[running_setup['sw']]]}

        subprocess.check_call(download[running_setup['sw']], stdout=logfile_handler)

        if (running_setup['sw'] == 'pcre'):
            subprocess.check_call(['tar', 'xf', 'pcre2-10.20.tar.gz', '--transform=s/pcre2-10.20/' + src_dir['pcre'] + '/'])

        os.chdir(src_dir[running_setup['sw']])
        git_revision = {'libxml':'3a76bfeddeac9c331f761e45db6379c36c8876c3',
                'pcre':'911bc707c0bfc81953d04b719dfcb39ae3520ba3',
                'http_parser':'feae95a3a69f111bc1897b9048d9acbc290992f9'}
        if running_setup['sw'] == 'libxml':
            subprocess.check_call(['git', 'checkout', '-b', 'old',
                git_revision[running_setup['sw']]], stdout=logfile_handler)
        os.chdir('../')
    if not os.path.exists(target_fuzzer):
        logging.error('Could not find target fuzzer: %s', target_fuzzer)
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

def fuzzer_exec_present():
    exec_path = os.path.join(pwd, exec_file[running_setup['sw']])
    if not os.path.isfile(exec_path):
        return False
    return True

def start_fuzzer_process():
    exec_path = os.path.join(pwd, exec_file[running_setup['sw']])
    corpus_path = os.path.join(pwd, running_setup['corpus'])
    if not fuzzer_exec_present():
        logging.error('The fuzzer executable could not be built.')
        return None

    env_vars = dict(os.environ)
    env_vars['ASAN_OPTIONS'] = '''poison_array_cookie=false:
        poison_partial=false:
        atexit=true:
        print_stats=true:
        malloc_context_size=0:
        detect_odr_violation=0:
        poison_heap=false:
        quarantine_size_mb=0:
        report_globals=0'''
    start_fuzzer_command = [exec_path, '-close_fd_mask=2', '-max_len=' + str(running_setup['max_len']),
            '-seed=' + str(running_setup['seed']), '-print_final_stats=1',
            '-max_total_time=' + str(running_setup['max_total_time'])]

    logging.debug('Start fuzzer command:\n\t%s', ' '.join(start_fuzzer_command))
    logging.debug('asap-cost-threshold:[%d]', running_setup['asap_cost_threshold'])

    return subprocess.Popen(start_fuzzer_command, env=env_vars, stdout=logfile_handler,
            stderr=subprocess.STDOUT)

def clear_dir(name):
    filelist = [f for f in os.listdir(name)]
    for f in filelist:
        os.remove(f)

def main(clean=False, full=False):

    if full:
        fuzzer_startup()
        return

    if clean or (not fuzzer_exec_present()):
        fuzzer_startup()

    cycles = 0
    while True:
        proc_popen = start_fuzzer_process()
        proc_data = Process(proc_popen)
        proc_data.start_monitoring()
        logging.debug('Started fuzzer process with pid: [%d]', proc_popen.pid)

        cycles += 1
        time.sleep(2)
        perf_command = ['perf', 'record', '-g', '-b', '-p', str(proc_popen.pid)]
        logging.debug('Start perf sampling command:\n\t%s', ' '.join(perf_command))
        perf_proc = subprocess.Popen(perf_command, stdout=logfile_handler)
        time.sleep(running_setup['sampling_time'])

        os.kill(perf_proc.pid, signal.SIGINT)
        logging.debug('Killed perf process with pid:[%d]', perf_proc.pid)
        time.sleep(5)

        #rebuild
        perf_to_gcov_command = ['create_llvm_prof', '--binary=' + exec_file[running_setup['sw']],
                '--profile=perf.data', '--out=perf.llvm_prof']
        logging.debug('Running perf to gcov command:\n\t%s', ' '.join(perf_to_gcov_command))
        subprocess.check_call(perf_to_gcov_command, stdout=logfile_handler)

        focused_build(cflags=focused_cflags, ldflags=focused_ldflags, ranlib=focused_ranlib)
        link_fuzzer()

        proc_data.terminate()
        try:
            os.kill(proc_data.pid, signal.SIGINT)
        except ProcessLookupError:
            pass
        time.sleep(1)
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
        self.running = False

    def crash_detector(self):
        while self.should_run:
            if self.popen.poll() != None:
                self.popen = start_fuzzer_process()
                self.pid = self.popen.pid
                self.original_popen.pid = self.pid
                self.running = True
                logging.debug('Restarted process with new pid [%s]', self.pid)
            time.sleep(3)

    def start_monitoring(self):
        self.crash_thread.start()

    def terminate(self):
        self.should_run = False
        logging.debug('The process with pid [%s] exited', self.pid)
        self.crash_thread.join()

def get_arg(param):
    if param.count('=') != 1:
        return ''
    return param.split('=')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--command')
    parser.add_argument('--corpus', default='CORPUS')
    parser.add_argument('--sampling-time', default=20)
    parser.add_argument('--max-len', default=2000)
    parser.add_argument('--seed', default=0)
    parser.add_argument('--max_total_time', default=20)
    parser.add_argument('--asap-cost-threshold', default=1000)
    parser.add_argument('--clean', action='store_true')
    parser.add_argument('--full', action='store_true')
    parser.add_argument('--sw', default='libxml')
    res = vars(parser.parse_args(sys.argv[1:]))

    if res['command'] == 'clean':
        try:
            subprocess.check_call(['rm', '-r', 'CORPUS'] + \
                    file_pattern('.', '*.o') + [exec_file[res['sw']], 'libFuzzer.a'])
        except subprocess.CalledProcessError as e:
            print(e)
        exit()

    running_setup['corpus'] = res['corpus']
    running_setup['sampling_time'] = int(res['sampling_time'])
    running_setup['max_len'] = int(res['max_len'])
    running_setup['seed'] = int(res['seed'])
    running_setup['max_total_time'] = int(res['max_total_time'])
    running_setup['asap_cost_threshold'] = int(res['asap_cost_threshold'])
    running_setup['sw'] = res['sw']

    build_dir = 'fuzzer-asap-%d-build' % running_setup['asap_cost_threshold']
    if not os.path.isdir(build_dir):
        os.mkdir(build_dir)

    target_fuzzer = os.path.join(os.getcwd(), source_file[running_setup['sw']])
    os.chdir(build_dir)

    logfile_handler = open(logfile, 'w')
    logging.basicConfig(level=logging.DEBUG)
    logging.getLogger().addHandler(logging.FileHandler(logfile))
    logging.debug("Arguments:\n%s", res)

    pwd = os.getcwd()
    prefix = os.path.join(pwd, 'inst')

    cov_flags = "-fsanitize-coverage=edge,indirect-calls,8bit-counters"
    basic_cflags = ['-O2', '-g', '-fsanitize=address', cov_flags]

    focused_cflags = basic_cflags + ['-fprofile-sample-use=' +
        os.path.join(os.getcwd(), llvm_prof_path), '-B/usr/bin/ld.gold',
        '-fsanitize=asap', '-mllvm', '-asap-cost-threshold=' + str(running_setup['asap_cost_threshold'])]

    focused_ldflags = ['-B/usr/bin/ld.gold']
    focused_ranlib = ['llvm-ranlib']

    include_dir = {'libxml':os.path.join(prefix, 'include/libxml2'),
            'pcre':os.path.join(prefix, 'include'),
            'http_parser':os.path.join(prefix, 'include')}
    build_fuzzer_cmd = ['clang++', '-g'] + basic_cflags + ['-c', '-std=c++11',
        '-I' + include_dir[running_setup['sw']], target_fuzzer]

    lib_path = {'libxml':os.path.join(prefix, 'lib/libxml2.a'),
            'pcre':os.path.join(prefix, 'lib/libpcre2-8.a'),
            'http_parser':os.path.join(prefix, 'lib/libhttp_parser.so')}

    logging.info('Running focused fuzzer with the following parameters:\n\t' +
            'corpus path:[%s] sampling_time:[%d] max_len:[%d] ' +
            'seed:[%d] asap-cost-threshold:[%d]',
            running_setup['corpus'], running_setup['sampling_time'],
            running_setup['max_len'], running_setup['seed'], running_setup['asap_cost_threshold'])

    main(clean=res['clean'], full=res['full'])
    logfile_handler.close()
