Once upon a time, the easiest way to setup a git server was with [Gitosis](http://git-scm.com/book/en/v1/Git-on-the-Server-Gitosis). But now, Gitosis hasn't been maintained for years! There's also much nicer ways to host  your own git repos, like [GitLab](https://about.gitlab.com/).

Unfortunately, if you've been using Gitosis for years, you probably have lots of working copies sitting around the reference your Gitosis server. You may also have infrastructure that expects Gitosis remotes to stay working, such as continuous integration or issue tracking systems. If you move to GitLab, those will all break!

gitosis2gitlab is a bridge from Gitosis remotes to your GitLab server. Just change your DNS settings so your old Gitosis domain points to your gitosis2gitlab server, and it will route git requests to your new GitLab server. Both reading (clone) and writing (push) are supported! Furthermore, gitosis2gitlab will obey the Gitosis permissions you already have.

Setup
=====

Suppose you have these existing servers:
* gitosis.example.com
* gitlab.example.com

You will first have to copy over your gitosis repositories to your GitLab server. To do so, SSH in to your GitLab server, and run ```setup-repos.sh gitosis.example.com```. By default, they'll be put in a GitLab group called ```imported```.

Then, you'll need to setup a new gitosis2gitlab server. If it's running Ubuntu, you can set it up by running ```setup-proxy.sh gitosis.example.com gitlab.example.com```. (If it's not running Ubuntu, see below for manual setup instructions.) When the script is finished, it will print out a SSH public key, eg: ```ssh-rsa AAAAB3Nz...```

Next, you have to create a user on GitLab so that gitosis2gitlab can access it. To do this, login to GitLab and get your API token from the "Account" page. Then run ```setup-gitlab.rb gitlab.example.com $TOKEN 'ssh-rsa AAAAB3Nz...'```.

Finally, you can switch your DNS settings so that gitosis.example.com points at your new gitosis2gitlab server. After that, you can disable your gitosis server, and users can still use the same git remote URLs as before.

Manual setup
============

If you can't or don't want to use the ```setup-proxy.sh``` script, you still can set up gitosis2gitlab manually on your server. Here's what you'll need:

* A user must exist that matches the user on your gitosis server, since the user name is part of the git remote. This user is usually called ```git```. Create that user on your gitosis2gitlab server if it doesn't already exist. You probably shouldn't use this user for anything else.
  * The gitosis2gitlab user needs to access your GitLab server, which it does via SSH public key authentication. Create a passwordless key pair for the user with ssh-keygen. You'll have to add the public key to a user on GitLab, so GitLab will accept connections.
  * SSH won't allow the user to login to access GitLab unless the GitLab server's host key is in the user's known_hosts file. You can add it by SSHing into your GitLab server manually, and answering "yes" when asked about the authenticity of the host.
* The gitosis2gitlab repository needs to be cloned into a location accessible to the user created above.
  * gitosis2gitlab is written in Ruby, and uses the ```inifile``` gem. Make sure Ruby and that gem are installed.
  * To keep the same permissions as your gitosis setup, gitosis2gitlab needs your gitosis-admin directory. Clone it into the gitosis2gitlab directory.
* To enable gitosis2gitlab, you generate an authorized_keys file based on the gitosis-admin directory. Run ```gitosis2gitlab.rb" authorized_keys```, and put the output into the user's ~/.ssh/authorized_keys file.

If you also want to setup GitLab manually instead of using the ```setup-gitlab.rb``` and ```setup-repos.rb``` scripts, here's what to do:

* Copy all your git repositories from gitosis to your GitLab server, and [import them into GitLab](https://gitlab.com/gitlab-org/gitlab-ce/blob/master/doc/raketasks/import.md). Make a note of the GitLab group that you imported them under.
* Create a new user on GitLab, to provide access to gitosis2gitlab. Make the user a member of the group from above, and give it the SSH public key from your gitosis2gitlab user.
