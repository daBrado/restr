require 'json'
require 'rack'

HTTP_OK = 200
HTTP_NOT_FOUND = 404
HTTP_INTERNAL_SERVER_ERROR = 500

class R
  def initialize(r_cmd=['R'])
    r_cmd_read, r_cmd_write = IO.pipe
    @r_out_read, @r_out_write = IO.pipe
    @cmd_read, @cmd_write = IO.pipe
    @data_read, @data_write = IO.pipe
    @r_exitstatus = nil
    @r_pid = spawn(
      *r_cmd, '--vanilla', '--slave',
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
  def initialize(r_cmd, r_namespaces, r_pool_size, log)
    @r_namespaces = r_namespaces
    @rq = SizedQueue.new r_pool_size
    @log = log
    Thread.new{loop{@rq<<R.new(r_cmd)}}
  end
  def call(env)
    req = Rack::Request.new env
    h = {"Access-Control-Allow-Origin" => "*"}
    return [HTTP_OK, h.merge({
      "Access-Control-Allow-Headers" => env['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'],
      "Access-Control-Allow-Methods" => env['HTTP_ACCESS_CONTROL_REQUEST_METHOD']
    }), []] if req.options?
    _, namespace, function, *args = req.path_info.split('/').map {|e| Rack::Utils::unescape e}
    return [HTTP_NOT_FOUND, h, []] unless @r_namespaces.empty? || @r_namespaces.include?(namespace)
    ignore_params = env['HTTP_IGNORE_PARAMS'].split(',').map{|p|p.strip} rescue []
    named_args = Hash[req.params.reject{|k,v| ignore_params.include? k}]
    numerify = lambda{|v| Hash[v.each_pair.map{|k,v| [k, numerify[v]]}] rescue v.map{|v| numerify[v]} rescue Integer(v) rescue Float(v) rescue v}
    args, named_args = [args, named_args].map{|v| numerify[v]}
    r_exitstatus, r_output, data_output = @rq.pop.call namespace, function, args, named_args
    if r_exitstatus != 0
      r_output.lines {|line| @log.error line.chomp}
      [HTTP_INTERNAL_SERVER_ERROR, h.merge({"Content-Type" => "text/plain"}), r_output.lines]
    else
      r_output.lines {|line| @log.warn line.chomp}
      [HTTP_OK, h.merge({"Content-Type" => "application/json"}), [data_output]]
    end
  end
end
