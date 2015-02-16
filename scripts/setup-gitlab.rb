#!/usr/bin/ruby
require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require 'optparse'

class Setup
  def initialize(params = {})
    @user = 'gitosis2gitlab'
    @group = 'imported'
    params.each { |k, v| instance_variable_set("@#{k}", v) }

    # Could be the key itself, or a file containing it
    @pubkey = IO.read(@pubkey) if File.exists?(@pubkey)

    @uri = URI(@server)
    @http = Net::HTTP.start(@uri.host, @uri.port,
      :use_ssl => @uri.scheme == 'https')
  end

  API_PATH = '/api/v3'
  def req(meth, path, opts = {})
    u = @uri.clone
    u.path += API_PATH + path
    u.query = URI.encode_www_form(opts[:query]) if opts[:query]
    u = opts[:uri] if opts[:uri]

    meth = Net::HTTP.const_get(meth.capitalize)
    req = meth.new(u)
    req['PRIVATE-TOKEN'] = @token
    req.set_form_data(opts[:body]) if opts[:body]
    resp = @http.request(req)
    raise "HTTP failure! #{resp.code} #{resp.message}" \
      unless Net::HTTPSuccess === resp
    return { :response => resp, :body => JSON.parse(resp.body) }
  end

  # Parse HTTP Link header
  def links(resp)
    return nil unless resp['Link']
    ret = {}
    resp['Link'].scan(/<([^>]*)>; rel="([^"]*)"/).each do |link, rel|
      ret[rel] = link
    end
    ret
  end

  def get(path, query = {})
    req('GET', path, :query => query)[:body]
  end
  def delete(path)
    req('DELETE', path)
  end

  def post(path, params)
    req('POST', path, :body => params)[:body]
  end
  def put(path, params)
    req('PUT', path, :body => params)[:body]
  end

  # GitLab doesn't do searching well, just page through the whole result set
  def paged(path, query = {}, &block)
    link = nil
    ret = []
    block ||= proc { |i| ret << i }
    loop do
      r = req('GET', path, :query => query, :uri => link)
      r[:body].each(&block)
      ls = links(r[:response]) or break
      link = ls['next'] or break
    end
    return ret
  end

  def find(path, value, key = 'name', query = {})
    paged(path, query) { |e| return e if e[key] == value }
    return nil
  end

  def group_create(name)
    # Check if it already exists first
    find('/groups', name) or post('/groups', :name => name, :path => name)
  end

  # Level 30 is 'Developer', see http://doc.gitlab.com/ce/api/groups.html
  def group_add(group_id, user_id, access_level = 30)
    # Check if already a member first
    path = "/groups/#{group_id}/members"
    user = find(path, user_id, "id")
    return if user && user['access_level'] == access_level

    member = "#{path}/#{user_id}"
    delete(member) if user # Re-add user with different access level
    post(path, :user_id => user_id,
      :access_level => access_level)
  end

  def user_create(username, params = {})
    # Check if it already exists first
    found = find('/users', username, 'username', :search => username)
    return found if found

    post('/users', :name => username, :username => username,
      :email => params[:email] || "#{SecureRandom.hex(16)}@example.com",
      :password => params[:password] || SecureRandom.hex(64)
    )
  end

  def key_create(user_id, title, key)
    path = "/users/#{user_id}/keys"
    key.chomp!
    return if find(path, key, "key")

    post(path, :title => title, :key => key)
  end

  KEY_TITLE = 'gitosis2gitlab'
  def run
    group = group_create(@group)
    user = user_create(@user)
    group_add(group['id'], user['id'])
    key_create(user['id'], KEY_TITLE, @pubkey)
  end
end

params = {}
parser = OptionParser.new do |opts|
  opts.banner = <<-EOF
setup-gitlab.rb [OPTIONS] SERVER TOKEN PUBKEY

Setup GitLab so it can be accessed by gitosis2gitlab.

SERVER is the URL to your GitLab server, eg: 'http://gitlab.example.com'.

TOKEN is a 20-character private token for an admin user of your GitLab
server. You can see your token at your /profile/account page on GitLab.

PUBKEY is the path to a file containing the SSH public key corresponding to
the 'git' user on your gitosis2gitlab installation.

EOF

  opts.on('-u', '--user USER',
    'The name of the user to create on GitLab (default: gitosis2gitlab)') \
    { |u| params[:user] = u }

  opts.on('-g', '--group GROUP',
    'The name of the group to create on GitLab (default: imported)') \
    { |g| params[:group] = g }

  opts.on('-h', '--help') { puts opts; exit }
end
parser.parse!

%w[server token pubkey].each do |k|
  params[k] = ARGV.shift or begin
    print "Argument #{k.upcase} missing!\n\n"
    puts parser.help
    exit
  end
end

Setup.new(params).run
