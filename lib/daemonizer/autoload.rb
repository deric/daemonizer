module Daemonizer
  # @private
  def self.__p(*path) File.join('lib/daemonizer', *path) end

  autoload :Config,         __p('config')
  autoload :Dsl,            __p('dsl')
  autoload :Errors,         __p('errors')
  autoload :CLI,            __p('cli')
  autoload :Daemonize,      __p('daemonize')
  autoload :Engine,         __p('engine')
  autoload :Worker,         __p('worker')
  autoload :WorkerPool,     __p('worker_pool')
  autoload :ProcessManager, __p('process_manager')

  include Errors
end
