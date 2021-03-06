#!/usr/bin/env ruby
#  Phusion Passenger - http://www.modrails.com/
#  Copyright (c) 2008, 2009 Phusion
#
#  "Phusion Passenger" is a trademark of Hongli Lai & Ninh Bui.
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#  THE SOFTWARE.
#
#
#  * Modified by Gleb Pomykalov for daemonizer - http://daemonizer.org
#
#

# ANSI color codes
RESET   = "\e[0m"
BOLD    = "\e[1m"
WHITE   = "\e[37m"
YELLOW  = "\e[33m"
BLUE_BG = "\e[44m"

module Daemonizer::Stats
  # Container for tabular data.
  class Table
  	def initialize(column_names)
  		@column_names = column_names
  		@rows = []
  	end

  	def add_row(values)
  		@rows << values.to_a
  	end

  	def add_rows(list_of_rows)
  		list_of_rows.each do |row|
  			add_row(row)
  		end
  	end

  	def remove_column(name)
  		i = @column_names.index(name)
  		@column_names.delete_at(i)
  		@rows.each do |row|
  			row.delete_at(i)
  		end
  	end

  	def to_s(title = nil)
  		max_column_widths = [1] * @column_names.size
  		(@rows + [@column_names]).each do |row|
  			row.each_with_index do |value, i|
  				max_column_widths[i] = [value.to_s.size, max_column_widths[i]].max
  			end
  		end

  		format_string = max_column_widths.map{ |i| "%#{-i}s" }.join("  ")
  		header = sprintf(format_string, *@column_names).rstrip << "\n"
  		if title
  			free_space = header.size - title.size - 2
  			if free_space <= 0
  				left_bar_size = 3
  				right_bar_size = 3
  			else
  				left_bar_size = free_space / 2
  				right_bar_size = free_space - left_bar_size
  			end
  			result = "#{BLUE_BG}#{BOLD}#{YELLOW}\n"
  			result << "#{"-" * left_bar_size} #{title} #{"-" * right_bar_size}\n"
  			if !@rows.empty?
  				result << WHITE
  				result << header
  			end
  		else
  			result = header.dup
  		end
  		if @rows.empty?
  			result << RESET
  		else
  			result << ("-" * header.size) << "#{RESET}\n"
  			@rows.each do |row|
  				result << sprintf(format_string, *row).rstrip << "\n"
  			end
  		end
  		result
  	end
  end

  class MemoryStats
  	class Process
  		attr_accessor :pid
  		attr_accessor :ppid
  		attr_accessor :threads
  		attr_accessor :vm_size              # in KB
  		attr_accessor :rss                  # in KB
  		attr_accessor :name
  		attr_accessor :private_dirty_rss    # in KB

  		def vm_size_in_mb
  			return sprintf("%.1f MB", vm_size / 1024.0)
  		end

  		def rss_in_mb
  			return sprintf("%.1f MB", rss / 1024.0)
  		end

  		def private_dirty_rss_in_mb
  			if private_dirty_rss.is_a?(Numeric)
  				return sprintf("%.1f MB", private_dirty_rss / 1024.0)
  			else
  				return "?"
  			end
  		end

  		def to_a
  			return [pid, ppid, vm_size_in_mb, private_dirty_rss_in_mb, rss_in_mb, name]
  		end
  	end
  	
  	attr_reader :pool
  	
  	def initialize(pool)
  	  @pool = pool
	  end
  	
  	def find_all_processes
  	  find_monitor + find_workers
	  end
	  
	  def find_workers
  	  self.list_processes(:match => /#{@pool.name} worker: instance \d{1,}/)
    end
    
    def find_monitor
  	  self.list_processes(:match => /#{@pool.name} monitor/)
    end
    
  	def print
  		puts
  		pool_processes = find_all_processes
  		if pool_processes.size == 0
  			puts "*** It seems like pool '#{@pool.name}' is not running"
  			return
		  end
		  puts
  		print_process_list("#{@pool.name} processes", pool_processes, :show_ppid => false)

  		if RUBY_PLATFORM !~ /linux/
  			puts
  			puts "*** WARNING: The private dirty RSS can only be displayed " <<
  				"on Linux. You're currently using '#{RUBY_PLATFORM}'."
  		elsif ::Process.uid != 0 && pool_processes.any?{ |p| p.private_dirty_rss.nil? }
  			puts
  			puts "*** WARNING: Please run this tool as root. Otherwise the " <<
  				"private dirty RSS of processes cannot be determined."
  		end
  	end
    
  	# Returns a list of Process objects that match the given search criteria.
  	#
  	#  # Search by executable path.
  	#  list_processes(:exe => '/usr/sbin/apache2')
  	#  
  	#  # Search by executable name.
  	#  list_processes(:name => 'ruby1.8')
  	#  
  	#  # Search by process name.
  	#  list_processes(:match => 'Passenger FrameworkSpawner')
  	  	
  	def list_processes(options)
  		if options[:exe]
  			name = options[:exe].sub(/.*\/(.*)/, '\1')
  			if RUBY_PLATFORM =~ /linux/
  				ps = "ps -C '#{name}'"
  			else
  				ps = "ps -A"
  				options[:match] = Regexp.new(Regexp.escape(name))
  			end
  		elsif options[:name]
  			if RUBY_PLATFORM =~ /linux/
  				ps = "ps -C '#{options[:name]}'"
  			else
  				ps = "ps -A"
  				options[:match] = Regexp.new(" #{Regexp.escape(options[:name])}")
  			end
  		elsif options[:match]
  			ps = "ps -A"
  		else
  			raise ArgumentError, "Invalid options."
  		end

  		processes = []
  		case RUBY_PLATFORM
  		when /solaris/
  			list = `#{ps} -o pid,ppid,nlwp,vsz,rss,comm`.split("\n")
  			threads_known = true
  		when /darwin/
  			list = `#{ps} -w -o pid,ppid,vsz,rss,command`.split("\n")
  			threads_known = false
  		else
  			list = `#{ps} -w -o pid,ppid,nlwp,vsz,rss,command`.split("\n")
  			threads_known = true
  		end
  		list.shift
  		list.each do |line|
  			line.gsub!(/^ */, '')
  			line.gsub!(/ *$/, '')

  			p = Process.new
  			if threads_known
  				p.pid, p.ppid, p.threads, p.vm_size, p.rss, p.name = line.split(/ +/, 6)
  			else
  				p.pid, p.ppid, p.vm_size, p.rss, p.name = line.split(/ +/, 5)
  				p.threads = "?"
  			end
  			p.name.sub!(/\Aruby: /, '')
  			p.name.sub!(/ \(ruby\)\Z/, '')
  			if p.name !~ /^ps/ && (!options[:match] || p.name.match(options[:match]))
  				# Convert some values to integer.
  				[:pid, :ppid, :vm_size, :rss].each do |attr|
  					p.send("#{attr}=", p.send(attr).to_i)
  				end
  				p.threads = p.threads.to_i if threads_known

  				if platform_provides_private_dirty_rss_information?
  					p.private_dirty_rss = determine_private_dirty_rss(p.pid)
  				end
  				processes << p
  			end
  		end
  		return processes
  	end

  private
  
  	def platform_provides_private_dirty_rss_information?
  		return RUBY_PLATFORM =~ /linux/
  	end

  	# Returns the private dirty RSS for the given process, in KB.
  	def determine_private_dirty_rss(pid)
  		total = 0
  		File.read("/proc/#{pid}/smaps").split("\n").each do |line|
  			line =~ /^(Private)_Dirty: +(\d+)/
  			if $2
  				total += $2.to_i
  			end
  		end
  		if total == 0
  			return nil
  		else
  			return total
  		end
  	rescue Errno::EACCES, Errno::ENOENT
  		return nil
  	end

  	def print_process_list(title, processes, options = {})
  		table = Table.new(%w{PID PPID VMSize Private Resident Name})
  		table.add_rows(processes)
  		if options.has_key?(:show_ppid) && !options[:show_ppid]
  			table.remove_column('PPID')
  		end
  		if platform_provides_private_dirty_rss_information?
  			table.remove_column('Resident')
  		else
  			table.remove_column('Private')
  		end
  		puts table.to_s(title)

  		if platform_provides_private_dirty_rss_information?
  			total_private_dirty_rss = 0
  			some_private_dirty_rss_cannot_be_determined = false
  			processes.each do |p|
  				if p.private_dirty_rss.is_a?(Numeric)
  					total_private_dirty_rss += p.private_dirty_rss
  				else
  					some_private_dirty_rss_cannot_be_determined = true
  				end
  			end
  			puts   "### Processes: #{processes.size}"
  			printf "### Total private dirty RSS: %.2f MB", total_private_dirty_rss / 1024.0
  			if some_private_dirty_rss_cannot_be_determined
  				puts " (?)"
  			else
  				puts
  			end
  		end
  	end
  end
end
