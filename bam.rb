#!/usr/bin/env ruby
require 'socket'
require 'timeout'
require 'yaml'
require 'rubygems'
require 'open-uri'
require 'rss/2.0' # URT News
require 'urbanterror'

class UrtBot
  def initialize(nick,channels,comchar,server,port=6667, ssl=false)
    @botnick = nick
    @channels = channels
    @comchar = comchar
    @socket = TCPSocket.open(server, port)
    if ssl
      # This general idea/method of doing this was taken from an early
      # version of Scott Olson's on_irc library.
      # See http://github.com/tsion/on_irc
      require 'openssl'
      ssl_context = OpenSSL::SSL::SSLContext.new()
      ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      @socket = OpenSSL::SSL::SSLSocket.new(@socket, ssl_context)
      @socket.sync = true
      @socket.connect
    end
      
    @socket.puts "NICK #{nick}"
    @socket.puts "USER #{nick} #{nick} #{nick} #{nick}"
    @rcon = YAML.load_file(File.join(File.dirname(__FILE__), 'rcon.yml'))
    @host_aliases = {
      'mn' => 'mostlynothing.info',
      'mi' => 'mostlyincorrect.info',
      'e' => 'games.elrod.me',
    }
  end
  
  def privmsg(channel, message)
    @socket.puts "PRIVMSG #{channel} :#{message}"
    puts "PRIVMSG #{channel} :#{message}"
  end
  
  def urt_info(host, port)
    begin
      urt = UrbanTerror.new(host, port.to_i)
      settings = urt.settings
      players = urt.players.sort_by { |player| -player[:score] }
      playersinfo = []
      if players.count != 0
        players.each do |player|
          player[:name] = "#{3.chr}04#{player[:name]}#{3.chr}" if player[:ping] == 999
          playersinfo << "#{player[:name].gsub(/ +/, ' ')} (#{player[:score]})"
        end
        players = "Players: #{playersinfo.join(', ')}"
      else
        players = "No players."
      end
      weapons = UrbanTerror.reverseGearCalc(settings['g_gear'].to_i)
      weapons = case weapons.size
      when 0
        'knives'
      when 6
        'all weapons'
      else
        weapons.join(', ')
      end
        gametype = UrbanTerror.matchType(settings['g_gametype'].to_i, true)
        "Map: #{2.chr}#{settings['mapname']}#{2.chr} (#{gametype} w/ #{weapons}). #{players}"
    rescue => error
      "[ERROR] #{error.message} (check your syntax and try again)."
    end
  end
  
  def news
    begin
      content = ''
      open('http://www.urbanterror.info/rss/news/all/') {|p| content = p.read }
      rss = RSS::Parser.parse(content, false).items[0]
      "#{2.chr}#{rss.title}#{2.chr} (#{rss.pubDate}) <#{rss.link}>: #{rss.description.gsub(/<\/?[^>]*>/, "")}"
    rescue => error
      "[ERROR] #{error.message}"
    end
  end
  
  def shortenurl(url)
    puts url
    newurl = ''
    open("http://is.gd/api.php?longurl=#{url}") {|p| newurl = p.read }
    return newurl
  end
  
  def reply(message, truncate=false)
    messages = message.scan(/.{1,420}/)
    
    messages.each do |message|
      urls = message.split.reject {|w| w !~ /https?\:.+/ }
      urls.each do |url|
        url =~ /(https?\:[\w\d\-\\\/\.]+)/i
        message.gsub!($1, shortenurl($1))
      end
    end
    
    if truncate
      privmsg(@channel, "#{@nick}: #{messages[0]}#{'...' if messages.count > 1}")
    else
      messages.each do |m|
        privmsg(@channel, "#{@nick}: #{m}")
      end
    end
    
  end

  def handle(nick,ident,cloak,channel,message)
    begin
      Timeout::timeout 5 do
        case message.strip
        when /^#{@comchar}urt (.*)/
          hosts = $1.split(';')
          alreadyused = []
          hosts.each do |host|
            if not alreadyused.include? host
              hostname, port = host.split(':', 2)
              port = port.to_i
              port = 27960 if port.zero?
              hostname = @host_aliases[hostname] if @host_aliases.has_key? hostname
              if host.empty?
                reply "Use .urt hostname[:port]"
              else
                reply urt_info(hostname, port)
              end
              alreadyused << host
            end
          end
        when /^#{@comchar}rcon (.*)/
          # Get hostname, port, command
          hostname, cmd = $1.split(' ', 2)
          hostname = @host_aliases[hostname] if @host_aliases.has_key? hostname
          hostname, port = hostname.split(':', 2)
          port = port.to_i
          port = 27960 if port.zero?
      
          if not @rcon.has_key? hostname
            reply "That hostname (#{hostname}) was not a member of the rcon-passwords configuration file."
          elsif not @rcon[hostname]['admins'].include? cloak
            reply "You are not listed as an admin of #{hostname}."
          else
            urt = UrbanTerror.new(hostname, port, @rcon[hostname]['password'])
            urt.rcon cmd
            reply "[SENT] \\rcon #{cmd}"
          end
        when /^#{@comchar}urtnews/
          reply(news, true)
        when /^#{@comchar}gear (.*)/
          origline = $1
          begin
            if origline =~ /^-?\d+$/
              weapons = UrbanTerror.reverseGearCalc(origline.to_i).join(', ')
              reply "#{weapons}"
            else
              number = UrbanTerror.gearCalc(origline.gsub(' ','').split(','))
              reply "#{number}"
            end
          rescue => error
            reply "#{error.message}"
          end
        end
      end
    rescue Timeout::Error
      reply "A timeout occured."
    end
  end
  
  def run
    while line = @socket.gets
      # Reload the passwords file every time, so we don't have to restart the bot every time.
      @rcon = YAML.load_file(File.join(File.dirname(__FILE__), 'rcon.yml'))
      puts line
      case line
      when /^:[\w.-]+ 433/
        @socket.puts "NICK #{@botnick}#{rand 100}"
      when /^:[\w.-]+ 001/
        # Join channels
        @channels.each do |channel|
          @socket.puts "JOIN #{channel}"
        end
      when /PING :(.*)/
        @socket.puts "PONG :#{$1}}"
      when /^:(.*)!(.*)@(.*) PRIVMSG (.*) :(.*)/
        @nick, @ident, @cloak, @channel, @message = $1, $2, $3, $4, $5
        handle($1,$2,$3,$4,$5)
      end
    end
  end
end

loop do
  current_host = Socket.gethostname

  if current_host == 'devel001' or current_host == 'internal001'
    bot = UrtBot.new('bam', ['#offtopic', '#bots', '#programming'], '\.', 'irc.ninthbit.net', 6667, false)
  else
    bot = UrtBot.new("bam#{rand 100}", ['#programming'], '-', 'irc.ninthbit.net', 6667, false)
  end

  bot.run
  sleep 5
end