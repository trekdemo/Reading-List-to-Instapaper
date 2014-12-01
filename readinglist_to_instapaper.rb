#!/usr/bin/env ruby
ENV['BUNDLE_GEMFILE'] = File.expand_path('../Gemfile', __FILE__)

require 'bundler/setup'
require 'nokogiri-plist'
require 'terminal-notifier'

require 'yaml/store'
require 'net/https'
require 'date'

class ReadingListToInstapaper
  SETTINGS_PATH = File.expand_path('~/.readinglist_instapaper')
  ICON_PATH = File.expand_path('./assets/instapaper.icns', __FILE__)
  DEFAULT_SETTINGS = {
    last_sync: Time.at(0),
    username: nil,
    password: nil,
  }

  def self.sync
    self.new.sync
  end

  def initialize
    ensure_settings!
  end

  def sync
    now = Time.now

    urls = latest_unread_reading_list_urls
    urls.each do |url|
      if save_url_to_instapaper(url)
        notify("Added to Instapaper", "Successfully added #{url}")
      else
        notify("Error Adding to Instapaper", "Could not add #{url}")
      end
    end

    puts 'Not link to transfer.' if urls.empty?
    save_last_sync(now)
  end

  private
  def latest_unread_reading_list_urls
    bookmark_categories = safari_bookmarks_plist['Children']
    reading_list        = bookmark_categories.find { |c| c['Title'] == 'com.apple.ReadingList' }

    reading_list['Children']
      .reject { |b| b['ReadingList'].has_key?('DateLastViewed') }           # unread
      .select { |b| b['ReadingList']['DateAdded'] }                         # double check
      .select { |b| b['ReadingList']['DateAdded'] > last_sync.to_datetime } # filter synced
      .sort   { |b| b['ReadingList']['DateAdded'] }
      .map    { |b| b['URLString'] }
  end

  def safari_bookmarks_plist
    file_content = %x[/usr/bin/plutil -convert xml1 -o - ~/Library/Safari/Bookmarks.plist]
    Nokogiri::PList(file_content)
  end

  def save_url_to_instapaper(url)
    Net::HTTP.start('www.instapaper.com', 443, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER) do |http|
      request = Net::HTTP::Get.new("/api/add?url=#{URI::escape(url)}")
      request.basic_auth(username, password)
      response = http.request(request)

      print "Saving '#{url}' to Instapaper..."
      response.is_a?(Net::HTTPSuccess).tap do |success|
        puts(success ? "\tcompleted" : "\tfailed")
      end
    end
  end

  def username
    settings.fetch(:username) { raise 'Username required for syncing' }
  end

  def password
    settings.fetch(:password) { raise 'Password required for syncing' }
  end

  def last_sync
    settings[:last_sync] || DEFAULT_SETTINGS[:last_sync]
  end

  def save_last_sync(time = nil)
    settings_file.transaction do |s|
      s[:settings][:last_sync] = time || Time.now
    end
  end

  def notify(subtitle, message)
    TerminalNotifier.notify(
      message,
      title: "Instapaper",
      subtitle: subtitle,
      appIcon: ICON_PATH,
    )
  end

  def settings
    settings_file.transaction(:read_only) { |c| c[:settings] || {} }
  end

  def settings_file
    YAML::Store.new(SETTINGS_PATH)
  end

  def ensure_settings!
    settings_file.transaction do |c|
      unless c[:settings]
        c[:settings] = DEFAULT_SETTINGS
        puts "Please add your Instapaper credentials in #{SETTINGS_PATH} file!"
      end
    end
  end

end

if __FILE__ == $0
  ReadingListToInstapaper.sync
end
