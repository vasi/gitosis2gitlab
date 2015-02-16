#!/bin/sh
set -e

usage() {
  echo "setup-proxy.sh [OPTIONS] GITOSIS_SERVER GITLAB_SERVER"
  echo
  echo "Setup gitosis2gitlab on this server."
  echo
  echo "GITOSIS_SERVER should be the domain (or IP address) of your gitosis"
  echo "server. GITLAB_SERVER should be the domain of your new GitLab server."
  echo
  echo "Options:"
  echo "  -u USER  # The user that gitosis expects to run under (default: git)"
  exit 2
}

parse_opts() {
  user="git"
  while getopts "u:h" opt; do
    case "$opt" in
      h|\?)
        usage
        ;;
      u)
        user="$OPTARG"
        ;;
    esac
  done
  shift $((OPTIND-1))
  gitosis_server="$1"
  gitlab_server="$2"
  [ -n "$gitlab_server" ] || usage
}

copy_server_keys() {
  # If we don't have the same server SSH keys as gitosis, clients will
  # complain. Copy them over, and restart SSH.
  if [ -n "$gitosis_server" ]; then
    sudo SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
      rsync "root@${gitosis_server}:/etc/ssh/*key*" /etc/ssh/
    sudo service ssh restart
  else
    echo "Warning! You will not have the SSH keys from your gitosis server."
  fi
}

add_user() {
  # Add a user under which gitosis2gitlab should run.
  homedir=$(eval echo "~$user")
  if [ "$homedir" = "~$user" ]; then
    # User doesn't already exist
    sudo useradd -m "$user"
    homedir=$(eval echo "~$user")
  fi
}

setup_ssh() {
  # Setup SSH for the new user.
  sudo -u "$user" install -d -m 0700 "$homedir/.ssh"

  # Generate a passwordless key, so we can access GitLab with it
  privkey="$homedir/.ssh/id_rsa"
  pubkey="$homedir/.ssh/id_rsa.pub"
  if [ ! -f "$privkey" ]; then
    sudo -u "$user" ssh-keygen -t rsa -N '' -f "$homedir/.ssh/id_rsa"
  fi

  # Add GitLab to our known_hosts, so SSH doesn't complain
  ssh-keyscan "$gitlab_server" 2> /dev/null | \
    sudo -u "$user" tee -a "$homedir/.ssh/known_hosts" >/dev/null
}

ensure_prerequisites() {
  git --version >/dev/null || sudo apt-get install -y git
  sudo bundle --version >/dev/null || sudo apt-get install -y bundler \
    || sudo apt-get install -y ruby-bundler
}

install_gitosis2gitlab() {
  # Checkout gitosis2gitlab, install gems
  if [ ! -e "$homedir/gitosis2gitlab" ]; then
    sudo -u "$user" -i git clone https://gitlab.com/vasi/gitosis2gitlab.git
  fi
  sudo bundle install --system --gemfile "$homedir/gitosis2gitlab/Gemfile"

  # Fetch the gitosis-admin directory, so we have the config files and such
  if [ ! -e "$homedir/gitosis2gitlab/gitosis-admin" ]; then
    if [ -n "$gitosis_server" ]; then
      git clone "$user@${gitosis_server}:gitosis-admin.git" \
        "$homedir/gitosis2gitlab/gitosis-admin"
    else
      echo "Warning! You'll need to fetch the gitosis-admin directory yourself!"
    fi
  fi

  # Create an authorized_keys file, so users can access gitosis2gitlab
  "$homedir/gitosis2gitlab/gitosis2gitlab.rb" authorized_keys | \
    sudo -u "$user" dd of="$homedir/.ssh/authorized_keys" 2> /dev/null
}

summarize() {
  echo
  echo "Done! Please edit gitosis2gitlab.yaml now."
  echo
  echo "Use the following SSH pubkey to setup GitLab:"
  sudo cat "$pubkey"
}

parse_opts "$@"
copy_server_keys
add_user
setup_ssh
ensure_prerequisites
install_gitosis2gitlab
summarize
