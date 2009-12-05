#!/usr/bin/ruby
require 'rubygems'
require 'time'
# Overmind - you are in charge!
# Boost the test driven development (TDD)! 
#
# Overmind takes a different approach than autotest
# avoiding the fuzziness and voodoo and giving the user
# the possibility to consiously choose, which tests to run.
#
# Written by Vladimir Dobriakov
# Parts inspired by the rstakeout.rb by Mike Clark.
# From http://www.pragmaticautomation.com/cgi-bin/pragauto.cgi/Monitor/StakingOutFileChanges.rdoc
#
# Running tests with JRuby introduces a huge start up delay:
# start JVM, load JRuby, load ActiveRecord etc.
#
# The trick is to preload the stuff and wait until the user
# saves her changes to the code and tests and run the tests fast then.
#
# You need to define your application- or task specific lurker class
# overriding `files`, prepare and main_work methods.
#
# Then you can run the overmind in one of two ways:
#
# * on the command line: 
#      ruby ./overmind.rb my_test_lurker MyTestLurker
#
# * from rake task
#      require 'overmind'
#      Overmind.run_endless_loop 'my_test_lurker', 'MyTestLurker'
#
class Lurker

  CLEAR_AND_RESET_TERMINAL = "\ec" #\e[2J"

  attr_accessor :identity

  def initialize(identity=nil)
    @identity = identity
  end

  def lurk
    puts "\n#{@identity}OVERMIND IS LOADING"
    extend_load_path
    memorize_files
    puts "\n#{@identity}STARTING PREPARE PHASE"
    prepare
    puts "\n#{@identity}LURKING IN THE BACKGROUND"
    puts "\n#{@identity}Press Ctrl-C a lot of times to interrupt, or try Ctrl-Z if the former does not work"
    wait
    puts CLEAR_AND_RESET_TERMINAL
    puts Time.now.rfc2822
    main_work
    puts "=> done"
  end

  # Default implementation, please override if needed!
  def files
    Dir['**/*.rb']
  end

  def extend_load_path
    $: << 'lib'
    $: << 'test'
  end

  # Default implementation for Rails, please override if needed!
  def prepare
    # clear log file(s)
    FileList["log/test*.log"].each do |log_file| # or use "log/*.log"
      f = File.open(log_file, "w")
      f.close
    end
  end

  def process_results_hook(res)
  end

  def memorize_files
    @file_states = {}

    files.each { |file|
      @file_states[file] = File.mtime(file)
    }
    #puts "Watching #{@file_states.keys.join(', ')}\n\nFiles: #{@file_states.keys.length}"
    puts "Watching #{@file_states.keys.length} files"
  end

  # returns the name of a file, changed since last time
  # or nil if there were no changes
  def changed_file
      @changed_file, @last_changed = @file_states.find { |file, last_changed|
        !File.exist?(file) or File.mtime(file) > last_changed
      }
      return @changed_file
  end

  def wait
    until changed_file do
      sleep 1
    end

    memorize_files

    while changed_file do # wait until all files were saved and everything calmed down
      puts "=> #{changed_file} changed"
      sleep 1
      memorize_files
    end
  end

end

class Overmind
  EXPIRATION_IN_SECONDS = 10
  IMG_FOLDER = '~/bin/autotest_images'

  def self.run_endless_loop(file_to_require, lurker_class, interpreter='jruby', dual_threaded=false)
    `rm -f /tmp/overmind_worker_works`
    threads = []
    0.upto(dual_threaded ? 1 : 0) do |i|
      threads[i] = Thread.new do
        while true
          cmd = "#{interpreter} -I#{File.dirname(__FILE__)} -e 'require %q(#{file_to_require});  #{lurker_class}.new(%q([#{i}])).lurk; puts %q(The End)'"
          puts "\n[#{i}]New iteration, running \n#{cmd}"
          res = ''
          IO.popen cmd do |io|
            io.each do |line|
              res << line
              puts line
              if line == "Started\n" 
                # char by char mode so we can better see the progress with dots
                io.each_char do |char|
                  print char
                  STDOUT.flush
                  res << char
                  break if char == "\n"
                end
              end
            end
          end
          puts 'rm'
          `rm -f /tmp/overmind_worker_works`
          process_unit_test_results res
          sleep 5
          yield res if block_given?
        end
      end
      sleep 15
    end
    threads.each do |thread|
      thread.join
    end
  end

  def self.process_unit_test_results(results)
    if results.include? 'tests'
      output = results.slice(/(\d+)\s+tests?,\s*(\d+)\s+assertions?,\s*(\d+)\s+failures?(,\s*(\d+)\s+errors)?/)
      if output
        $~[3].to_i + $~[5].to_i > 0 ? notify_fail(output) : notify_pass(output)
      end
    else
      output = results.slice(/(\d+)\s+examples?,\s*(\d+)\s+failures?(,\s*(\d+)\s+not implemented)?/)
      if output
        $~[2].to_i > 0 ? notify_fail(output) : notify_pass(output)
      end
    end
    # TODO Generic notification for other actions
  end

  def self.notify(title, msg, img, pri=0, sticky="")
    if not `which notify-send`.strip.empty? # gnome
      system "notify-send -t #{EXPIRATION_IN_SECONDS * 1000} -i #{File.join(IMG_FOLDER,img)} '#{title}' '#{msg}'"
    end
    # For Mac users use growlnotify
    # system "growlnotify -n autotest --image ~/.autotest_images/#{img} -p #{pri} -m #{msg.inspect} #{title} #{sticky}"
    #
    # For KDE users: TODO implement
  end

  def self.notify_fail(output)
    notify "FAIL", "#{output}", "fail.png", 2
  end

  def self.notify_pass(output)
    notify "Pass", "#{output}", "pass.png"
  end

end

if __FILE__ == $0
  if ARGV[0] and ARGV[1]
    Overmind.run_endless_loop ARGV[0], ARGV[1]
  else
    puts "Please provide the bootstrap file name as the first parameter and the Lurker class name as the second."
    puts "Example: ruby ./overmind.rb my_test_lurker MyTestLurker"
  end
end

