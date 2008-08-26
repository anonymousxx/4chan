#!/usr/bin/ruby

require 'rubygems'
require 'hpricot'
require 'open-uri'
require 'fileutils'

# TODO catch Timeout::Error from thread
# TODO make directories configurable. CL-Argument?
module Four

  module Output
    def debug(text)
      puts text
    end
    def log(statement='')
      puts "#{self.class} #{self} - #{statement}"
    end
  end

  module ImageFetcher
    def fetch_images
      images.each do |image|
        Image.new(image,channel).fetch_if_wanted!
      end
      puts
    end
    def images
      doc ? doc/"span.filesize a" : []
    end
    def mark_image_as_fetched(image_url)
      Image.mark_as_fetched image_url
    end
    def image_fetched?(image_url)
      Image.fetched? image_url
    end
  end

  module Robustness
    def with_rubustness
      tries = 0
      begin
        yield
      rescue Timeout::Error, EOFError
        tries += 1
        if tries < 5
          log("error")
          retry
        else
          log("epic fail, tried #{tries} times")
        end
      rescue OpenURI::HTTPError
        log("too late. it's gone.")
      end
    end
  end

  module Page
    include Robustness
    attr_reader :doc
    def fetch!
      with_rubustness do
        @doc = open(url) { |f| Hpricot(f) }
        log("fetched. Now the Images..")
      end
    end
    def to_s
      url
    end
  end

  class Image
    include FileUtils
    include Output
    include Robustness
    attr_reader :url, :filename, :channel
    @@fetched = {}
    def self.mark_as_fetched(url)
      @@fetched[url] = true
    end
    def mark_as_fetched
      self.class.mark_as_fetched url
    end
    def self.fetched?(url)
      @@fetched.has_key? url
    end
    def self.fetched_count
      @@fetched.length
    end
    def fetched?
      self.class.fetched? url
    end
    def initialize(element,chan)
      @url = element[:href]
      @filename = element.inner_html
      @channel = chan
    end
    def fetch_if_wanted!
      if wanted?
        fetch!
      end
    end
    def fetch!
      with_rubustness do
        response = Net::HTTP.get_response(URI.parse(url))
        if response.is_a? Net::HTTPSuccess
          save(response.body)
          log('fetched')
          mark_as_fetched
          log_as_fetched
        else
          log("epic fail")
        end
      end
    end
    def save(data)
      mkdir_p directory
      File.open fullpath, 'w' do |file|
        file.write data
      end
    end
    def wanted?
      if fetched?
        log("already fetched")
        return false
      elsif File.exists? fullpath
        log("file exists")
        mark_as_fetched
        return false
      else
        return true
      end
    end
    def directory
      File.join ENV['HOME'], 'images', '4chan', channel.section
    end
    def fullpath
      File.join directory, filename
    end
    def log_as_fetched
      File.open channel.fetched_images_path, 'a' do |file|
        file.puts url
      end
    end
    def to_s
      url
    end
  end
  class Reply
    include Output
    include ImageFetcher
    include Page
    attr_reader :url, :channel
    def initialize(elem,chan)
      @channel = chan
      @url = "http://cgi.4chan.org/#{channel.section}/#{elem[:href]}"
    end
  end
  class Chan
    include Output
    include Page
    include ImageFetcher
    MaxPages = 10
    attr_accessor :section
    attr_accessor :page
    attr_reader :channel
    def initialize(chan=nil)
      @section = (chan.nil? or chan.empty?) ? 's' : chan
      @channel = self # HACK for ImageFetcher
      @page = nil
      $stdout.sync=true
    end
    def reply_links
      doc ? (doc/"//a[@href^='res/'").select {|a| a.inner_html == 'Reply' } : []
    end
    def fetch_replies
      reply_links.each do |link|
        reply = Reply.new(link, self)
        reply.fetch!
        reply.fetch_images
      end
    end
    def next_page
      @page ||= 1
      @page += 1
      log("next page => #{@page}")
    end
    def url
      if @page && @page > 1
        "http://cgi.4chan.org/#{section}/#{page}.html"
      else
        "http://cgi.4chan.org/#{section}/"
      end
    end
    def browse
      startup
      @page = 0
      MaxPages.times do
        next_page
        fetch!
        fetch_images
        fetch_replies
      end
    end
    def browse_forever
      while(true) do
        browse
        sleep 23
      end
    end

    def fetched_images_path
      File.join ENV['HOME'], 'images', '4chan', section + '_fetched.txt'
    end

    private
    def startup
      path = fetched_images_path
      if File.exists? path
        File.open path do |file|
          file.each_line do |image|
            mark_image_as_fetched image.chomp
          end
        end
      end
      log("Remembered #{Image.fetched_count} images")
    end
  end
end

begin
  Four::Chan.new(ARGV.shift).browse_forever
rescue Exception => e
  puts "Exception: #{e.class}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
  exit 1
end
