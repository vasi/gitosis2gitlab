#!/bin/sh
set -e

die() {
  echo "$@" 1>&2
  exit 2
}

setup() {
  git checkout -- gitosis2gitlab.yaml

  rm -rf gitosis-admin
  cp -r test/gitosis-admin .
  mkdir -p gitosis-admin/keydir
  cp test/*.pub gitosis-admin/keydir/

  # Setup a test bin dir
  mkdir gitosis-admin/bin
  ln -s /bin/echo gitosis-admin/bin/ssh
  export PATH="$PWD/gitosis-admin/bin:$PATH"
}

test_authorized_keys() {
  ruby ./gitosis2gitlab.rb authorized_keys > out.tmp
  grep -q "passthrough testuser2" out.tmp || die No user 2
  grep -q "passthrough testuser[^2]" out.tmp || die No user 1
  grep -q "AAAAB3NzaC1yc2EAAAADAQABAAABAQCywzb" out.tmp || die No SSH key
  grep -q "no-pty" out.tmp || die PTY allowed
  rm -f out.tmp
}

test_access() {
  if ruby ./gitosis2gitlab.rb access $1 $2 $3 > /dev/null; then
    [ $4 = yes ] || fail=yes
  else
    [ $4 = no ] || fail=yes
  fi
  [ -z "$fail" ] || die "Bad access for user=$1 repo=$2 writable=$3"
}

test_accesses() {
  test_access testuser gitosis/gitlab write no
  test_access testuser gitosis/gitlab '' yes
  test_access testuser2 gitosis/gitlab write no
  test_access testuser2 gitosis/gitlab '' yes
  test_access fake gitosis/gitlab write no
  test_access fake gitosis/gitlab '' no
  test_access testuser testrepo write yes
  test_access testuser testrepo '' yes
  test_access testuser2 testrepo write no
  test_access testuser2 testrepo '' no
  test_access fake testrepo write no
  test_access fake testrepo '' no
  test_access testuser fake write no
  test_access testuser fake '' no
  test_access testuser2 fake write no
  test_access testuser2 fake '' no
  test_access fake fake write no
  test_access fake fake '' no
}

test_passthroughs() {
  out=$(SSH_ORIGINAL_COMMAND="git-upload-pack 'gitosis/gitlab.git'" \
    ruby ./gitosis2gitlab.rb passthrough testuser)
  [ "$out" = "-i .ssh/id_rsa git@gitlab.example.com git-upload-pack imported/gitosis-gitlab.git" ] || die Bad passthrough SSH command

  if ruby ./gitosis2gitlab.rb passthrough testuser 2>/dev/null; then
    die Missing SSH_ORIGINAL_COMMAND should cause error
  fi
  if SSH_ORIGINAL_COMMAND="rm /etc" ruby ./gitosis2gitlab.rb passthrough testuser 2>/dev/null; then
    die Bad SSH_ORIGINAL_COMMAND should cause error
  fi
  if SSH_ORIGINAL_COMMAND="git-receive-pack 'gitosis/gitlab.git'" ruby ./gitosis2gitlab.rb passthrough testuser 2>/dev/null; then
    die Bad perms should cause error
  fi
}

setup
test_authorized_keys
test_accesses
test_passthroughs
echo 'Looks good!'
