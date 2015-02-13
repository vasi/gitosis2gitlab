Once upon a time, the easiest way to setup a git server was with [Gitosis](http://git-scm.com/book/en/v1/Git-on-the-Server-Gitosis). But now, Gitosis hasn't been maintained for years! There's also much nicer ways to host  your own git repos, like [GitLab](https://about.gitlab.com/).

Unfortunately, if you've been using Gitosis for years, you probably have lots of working copies sitting around the reference your Gitosis server. You may also have infrastructure that expects Gitosis remotes to stay working, such as continuous integration or issue tracking systems. If you move to GitLab, those will all break!

gitosis2gitlab is a bridge from Gitosis remotes to your GitLab server. Just change your DNS settings so your old Gitosis domain points to your gitosis2gitlab server, and it will route git requests to your new GitLab server. Both reading (clone) and writing (push) are supported! Furthermore, gitosis2gitlab will obey the Gitosis permissions you already have.

Configuration
=============



Tutorial
========

Suppose you have these servers:
* gitosis.example.com
* gitlab.example.com
* gitosis2gitlab.example.com

I will assume gitlab.example.com and gitosis2gitlab are running Ubuntu 14.04, but other distributions should work with minor changes.

On gitosis2gitlab.example.com:
* We need the same SSH key to be used for this server as the old one, so clients don't break:
```
rsync -av root@gitosis.example.com:/etc/ssh/*key* /etc/ssh/
service ssh restart
```
* Add a git user:
```useradd -m git```
* Create a SSH key for that user:
```
sudo -u git ssh-keygen -t rsa -N '' -f ~git/.ssh/id_rsa
cat ~git/.ssh/id_rsa.pub
```
* Install necessary packages: ```sudo apt-get install git bundler```
* Checkout gitosis2gitlab:
```sudo -u git -i git clone https://gitlab.com/vasi/gitosis2gitlab.git```
** Install Ruby gems: ```sudo bundle install --gemfile ~git/gitosis2gitlab/Gemfile --system```
* Configure gitosis2gitlab
** Copy your gitosis-admin directory over:
```git clone git@gitosis.example.com:gitosis-admin.git ~git/gitosis2gitlab/gitosis-admin```
** Edit ~git/gitosis2gitlab/gitosis2gitlab.yaml, change the ```host``` to ```git@gitlab.example.com```
** Make sure we know about that host:
```ssh-keyscan gitlab.example.com | sudo -u git tee -a ~git/.ssh/known_hosts```
** Create an authorized_keys file:
```~git/gitosis2gitlab/gitosis2gitlab.rb authorized_keys | sudo -u git dd of=~git/.ssh/authorized_keys```

On gitlab.example.com:
* In the GitLab UI
** Create a new group ```imported```
** Create a GitLab user ```gitosis2gitlab```
*** Give this user access to the group ```imported```
*** Add the public key from git@gitosis2gitlab.example.com as a SSH key for this user
* Put your repos in the proper locations
** Rsync over your repos:
```rsync -avz gitosis.example.com:~git/repositories/ ~/repositories/```
** Reorganize your repos into the ```imported``` group's directory:
```
cd
git clone https://gitlab.com/vasi/gitosis2gitlab.git
~/gitosis2gitlab/scripts/repo-reorg - ~/repositories /var/opt/gitlab/git-data/repositories/imported
chown -R git /var/opt/gitlab/git-data/repositories/imported
```

Now switch your DNS so that gitosis.example.com points to gitosis2gitlab.example.com . All your existing git repos should still work, but now they're connected to GitLab instead of Gitosis!
