require 'logger'
require 'json'
require 'rack'

class R
  def initialize
    r_cmd_read, r_cmd_write = IO.pipe
    @r_out_read, @r_out_write = IO.pipe
    @cmd_read, @cmd_write = IO.pipe
    @data_read, @data_write = IO.pipe
    @r_exitstatus = nil
    @r_pid = spawn(
      'R', '--vanilla', '--slave',
      :in => r_cmd_read,
      [:out, :err] => @r_out_write,
      @cmd_read => @cmd_read,
      @data_write => @data_write
    )
    r_cmd_write.write("
      r <- file('/dev/fd/#{@cmd_read.fileno}', open='r', raw=T)
      w <- file('/dev/fd/#{@data_write.fileno}', open='w', raw=T)
      cmd <- rjson::fromJSON(readLines(r))
      result <- do.call(
        get(cmd$'function', asNamespace(cmd$namespace)),
        c(as.list(cmd$args), cmd$named_args)
      )
      cat(rjson::toJSON(result), file=w)
      close(r)
      close(w)
      q()
    ")
    r_cmd_write.close
    @cmd_read.close
    @data_write.close
  end
  def call(namespace, function, args, named_args)
    @cmd_write.puts({namespace: namespace, function: function, args: args, named_args: named_args}.to_json) rescue nil
    @cmd_write.close
    _, @r_exitstatus = Process.wait2 @r_pid
    @r_out_write.close  # Why doesn't R close this when it exits?
    return @r_exitstatus, @r_out_read.read, @data_read.read
  end
end

class RESTR
  R_POOL_SIZE = 7
  def initialize(r_namespaces, r_pool_size:R_POOL_SIZE, log:Logger.new(STDERR))
    @r_namespaces = r_namespaces
    @log = log
    @rq = SizedQueue.new r_pool_size
    Thread.new{loop{@rq<<R.new}}
  end
  def numerify v
    Hash[v.each_pair.map{|k,v| [k, numerify(v)]}] rescue
      v.map{|v| numerify v} rescue
        Integer(v) rescue Float(v) rescue v
  end
  def call(env)
    req = Rack::Request.new env
    h = {"Access-Control-Allow-Origin" => "*"}
    return [HTTP_OK, h.merge({
      "Access-Control-Allow-Headers" => env['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'],
      "Access-Control-Allow-Methods" => env['HTTP_ACCESS_CONTROL_REQUEST_METHOD']
    }), []] if req.options?
    _, namespace, function, *args = req.path_info.split('/').map {|e| Rack::Utils::unescape e}
    return [404, h, []] unless @r_namespaces.empty? || @r_namespaces.include?(namespace)
    ignore_params = env['HTTP_IGNORE_PARAMS'].split(',').map{|p|p.strip} rescue []
    named_args = Hash[req.params.reject{|k,v| ignore_params.include? k}]
    args, named_args = [args, named_args].map{|v| numerify v}
    r_exitstatus, r_output, data_output = @rq.pop.call namespace, function, args, named_args
    if r_exitstatus != 0
      r_output.lines {|line| @log.error line.chomp}
      [500, h.merge({"Content-Type" => "text/plain"}), ['R Error']]
    else
      r_output.lines {|line| @log.warn line.chomp}
      [200, h.merge({"Content-Type" => "application/json"}), [data_output]]
    end
  end
end
