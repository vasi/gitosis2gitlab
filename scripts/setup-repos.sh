#!/bin/sh
set -e

usage() {
  echo "setup-repos.sh [OPTIONS] REPO_SRC"
  echo
  echo "Setup repositories for gitosis2gitlab. Run this on your GitLab server."
  echo
  echo "The REPO_SRC indicates where to get repositories from. It can be:"
  echo "  * A path to a local directory, or"
  echo "  * A domain name or IP address of a Gitosis server, or"
  echo "  * An rsync source specification, ending with a slash."
  echo
  echo "Options:"
  echo "  -g GROUP       # GitLab group under which the repos should live"
  echo "                 # (default: 'imported')"
  echo "  -s SEPARATOR   # Change slashes in repo names into this character"
  echo "                 # (default: '-')"
  echo "  -d REPO_DIR    # Where GitLab expects to find repositories"
  echo "                 # (default: discovered with Rake)"
  echo "  -r RAKE_CMD    # How to execute Rake"
  echo "                 # (default: auto-discovered)"
  echo
  exit 2
}

parse_opts() {
  group='imported'
  separator='-'
  while getopts "s:g:r:d:h" opt; do
    case "$opt" in
      h|\?)
        usage
        ;;
      g)
        group="$OPTARG"
        ;;
      s)
        separator="$OPTARG"
        ;;
      r)
        rake_cmd="$OPTARG"
        ;;
      d)
        repo_dir="$OPTARG"
        ;;
    esac
  done
  shift $((OPTIND-1))
  repo_src="$1"
  [ -n "$repo_src" ] || usage
}

find_repo_dir() {
  # User specified it, assume it's correct
  if [ -n "$repo_dir" ]; then return; fi
  echo -n "Finding where to put repositories... "

  # Find a Rake
  if [ ! -n "$rake_cmd" ]; then
    if command -v gitlab-rake > /dev/null 2>&1; then
      # Omnibus install
      rake_cmd="gitlab-rake"
    else
      # Assume we're in the gitlab directory, I guess
      rake_cmd="sudo -u git -H bundle exec rake"
    fi
  fi

  repo_dir=$($rake_cmd gitlab:env:info | awk '/^Repositories:/ { print $2 }')
  if [ ! -n "$repo_dir" ]; then
    echo
    echo "Can't find where to place repositories!" 1>&2
    echo "Try setting the -d or -r options." 1>&2
    exit -1
  fi
  echo "$repo_dir"
}

fetch_repos() {
  # If it's local, we're cool
  if [ -d "$repo_src" ]; then return; fi

  # Find the rsync source
  case "$repo_src" in
    *:*)
      # Looks like rsync
      rsync_src="$repo_src"
      ;;
    *)
      # Must be just a server, assume default source dir
      rsync_src="$repo_src:~git/repositories/"
      ;;
  esac

  # Check for rsync progress2 support
  if rsync --help | grep -q -- --info; then
    rsync_progress="--info progress2"
  fi

  # Use a temp directory
  repo_src="$(dirname $repo_dir)/tmp-gitosis2gitlab"
  autodelete=yes

  echo "Fetching repos from $rsync_src to $repo_src..."
  rsync -az --partial $rsync_progress "$rsync_src" "$repo_src/"
}

reorg_repos() {
  echo "Moving repositories into place..."

  group_dir="$repo_dir/$group"
  mkdir -p "$group_dir"

  find "$repo_src" -name '*.git' -prune -printf "%P\n" | sort | \
  while read repo; do
    # Turn slashes into separators
    newname=$(echo "$repo" | tr / "$separator")
    dst="$group_dir/$newname"

    if [ -e "$dst" ]; then
      echo "Repo $newname already exists, skipping it!"
    else
      mv "$repo_src/$repo" "$dst"
    fi
  done

  echo "Changing ownership of repositories..."
  chown -R --reference="$repo_dir" "$group_dir"
}

import_repos() {
  echo "Importing repos into GitLab..."
  $rake_cmd gitlab:import:repos
}

delete_tmp() {
  if [ "x$autodelete" = "xyes" ]; then
    echo "Removing temp dir $repo_src..."
    rm -rf "$repo_src"
  fi
}

parse_opts "$@"
find_repo_dir
fetch_repos
reorg_repos
import_repos
delete_tmp

