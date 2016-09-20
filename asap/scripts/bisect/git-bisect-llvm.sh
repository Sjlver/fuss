# Helper functions to use git bisect with LLVM.

checkout() {
    cd $LLVM_SRC
    local committer_date="$(git log --pretty=format:%cd -n1 'HEAD')"
    cd $LLVM_SRC/tools/clang
    git checkout "$(git rev-list -n 1 --before="$committer_date" origin/google/testing)"
    cd $LLVM_SRC/projects/compiler-rt
    git checkout "$(git rev-list -n 1 --before="$committer_date" origin/google/testing)"
}

build() {
    cd $LLVM_BUILD
    ninja
}

# Go for it!
#checkout  || exit 125
#build  || exit 125
#run_test
