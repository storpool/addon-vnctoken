#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# -------------------------------------------------------------------------- #
# Copyright 2019-2020, StorPool                                              #
# Portions copyright OpenNebula Project, OpenNebula Systems                  #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

ONE_LOCATION = ENV['ONE_LOCATION']

if !ONE_LOCATION
    RUBY_LIB_LOCATION = '/usr/lib/one/ruby'
    GEMS_LOCATION     = '/usr/share/one/gems'
    LOG_LOCATION      = '/var/log/one'
    VAR_LOCATION      = '/var/lib/one'
    ETC_LOCATION      = '/etc/one'
else
    RUBY_LIB_LOCATION = ONE_LOCATION + '/lib/ruby'
    GEMS_LOCATION     = ONE_LOCATION + '/share/gems'
    VAR_LOCATION      = ONE_LOCATION + '/var'
    LOG_LOCATION      = ONE_LOCATION + '/var'
    ETC_LOCATION      = ONE_LOCATION + '/etc'
end

ONEVNC_AUTH        = VAR_LOCATION + "/.one/vnctoken_auth"
SUNSTONE_AUTH      = VAR_LOCATION + "/.one/sunstone_auth"
ONEVNC_LOG         = LOG_LOCATION + "/vnctoken.log"
CONFIGURATION_FILE = ETC_LOCATION + "/vnctoken-server.conf"
SUNSTONE_CONF_FILE = ETC_LOCATION + "/sunstone-server.conf"

if File.directory?(GEMS_LOCATION)
    Gem.use_paths(GEMS_LOCATION)
end

$LOAD_PATH << RUBY_LIB_LOCATION
$LOAD_PATH << RUBY_LIB_LOCATION + '/cloud'

require 'rubygems'
require 'sinatra'
require 'yaml'
require 'xmlrpc/marshal'

require 'CloudAuth'
require 'CloudServer'

require 'opennebula'

include OpenNebula

class Hash
  def to_xml
    map do |k, v|
      text = Hash === v ? v.to_xml : v
      "<%s>%s</%s>" % [k.upcase, text, k.upcase]
    end.join
  end
end

begin
    $conf = YAML.load_file(SUNSTONE_CONF_FILE)
    $conf.merge!(YAML.load_file(CONFIGURATION_FILE))
    CloudServer.print_configuration($conf)
rescue Exception => e
    STDERR.puts "Error parsing config file #{CONFIGURATION_FILE}: #{e.message}"
    exit 1
end

set :bind, $conf[:host]
set :port, $conf[:port]

set :conf, $conf

include CloudLogger
logger = enable_logging(ONEVNC_LOG, $conf[:debug_level].to_i)

if File.file?(ONEVNC_AUTH)
    ENV["ONE_CIPHER_AUTH"] = ONEVNC_AUTH
else
    logger.info { "#{ONEVNC_AUTH} not found. Trying sunstone auth." }
    ENV["ONE_CIPHER_AUTH"] = SUNSTONE_AUTH
end

begin
    $cloud_auth = CloudAuth.new($conf, @logger)
rescue => e
    logger.error { "Error initializing authentication system" }
    logger.error { e.message }
    exit(-1)
end

configure do
    set :cloud_auth, $cloud_auth
    set :xmlrpc, XMLRPC::Create.new
    set :marshal, XMLRPC::Marshal.new
end

before do
    content_type 'application/xml', :charset => 'utf-8'
    request.body.rewind
    @request_body = request.body.read
end

helpers do

    def get_vm(vm_id, client)
        vm = VirtualMachine.new_with_id(vm_id, client)
        rc = vm.info

        if OpenNebula.is_error?(rc)
            logger.error {"VMID:#{vm_id} vm.info error: #{rc.message}"}
            return [0x0400, rc.message]
        end

        [0x0000, vm]
    end

    def generate_token(vm_id, vm_host, vnc_port)
        random_str = rand(36**20).to_s(36)
        token = "#{random_str}: #{vm_host}:#{vnc_port}"
        token_file = "one-#{vm_id}"
        token_folder_name = settings.conf[:token_folder_name]
        token_folder = "#{VAR_LOCATION}/#{token_folder_name}"

        begin
            f = File.open(File.join(token_folder, token_file), 'w')
            f.write(token)
            f.close
        rescue Exception => e
            logger.error e.message
            return [0x4000 , "Cannot create VNC proxy token. #{e.message}"]
        end

        [0x0000, random_str]
    end

    def get_vm_data(auth, vm_id)
        begin
            client = OpenNebula::Client.new(auth, settings.conf[:one_xmlrpc])
        rescue Exception => e
            logger.error { "User cannot be authenticated" }
            logger.error { e.message }
            return [0x0200, e.message]
        end

        params = { :id => vm_id }
        ret, vm = get_vm(vm_id, client)
        if ret != 0
            logger.error { "get_vm(#{vm_id}):#{vm} (ret:#{ret})" }
            return [ret, vm] if ret != 0
        end

        if vm.state == 3 and vm.lcm_state == 3
            host = vm['HISTORY_RECORDS/HISTORY[last()]/HOSTNAME']
            params[:host]  = host.nil? ? '' : host
            type = vm['TEMPLATE/GRAPHICS/TYPE']
            params[:type] = type.nil? ? '' : type

            if type == 'VNC'
                port = vm['TEMPLATE/GRAPHICS/PORT'].to_i
                params[:port] = port
                listen = vm['TEMPLATE/GRAPHICS/LISTEN']
                params[:listen] = listen.nil? ? '' : listen
                pw = vm['TEMPLATE/GRAPHICS/PASSWD']
                params[:password] = pw.nil? ? '' : pw

                wss = settings.conf[:vnc_proxy_support_wss]
                if (wss == "yes") || (wss == "only") || (wss == true)
                      params[:wss] = true
                else
                      params[:wss] = false
                end

                ret, token = generate_token(vm_id, host, port)
                if ret == 0
                    params[:token] = token
                else
                    return [ret, token]
                end
            else
               return [0x0400, "Graphics type '#{type}' but 'VNC' expected"]
            end

        else
            err = "Unsupported VM state! STATE:#{vm.state} LCM_STATE:#{vm.lcm_state}"
            return [0x0800, err]
        end
        [0x0000, params]
    end


    def process_request()
        #logger.debug { "#{@request_body}" }
        data = settings.marshal.load_call(@request_body)
        #logger.debug { "Request:#{data}" }

        methods = ['one.vm.vnctoken', 'one.vm.vnctokenonly', 'one.vm.vnc']
        method = data[0]
        unless methods.include?(method)
            return [0x1000, "Unknown method '#{method}'. Expected #{methods}"]
        end

        ret, vmdata = get_vm_data(data[1][0], data[1][1])

        if ret != 0
            return [ret, vmdata]
        end

        if method == 'one.vm.vnctokenonly'
            return [0x0000, vmdata[:token]]
        elsif method == 'one.vm.vnc'
            return [0x0000, "<VM>#{vmdata.to_xml}</VM>"]
        end

        [0x0000, vmdata]
    end

end

get '/RPC2*' do
    res, data = process_request()

    if res == 0
        response = [[true, data, res]]
    else
        logger.error { "#{data} //#{res}" }
        response = [[false, data, res]]
    end

    xmlrpc_response = settings.xmlrpc.methodResponse(true, *response)

    [200, xmlrpc_response]
end

post '/RPC2*' do
    res, data = process_request()

    if res == 0
        response = [[true, data, res]]
    else
        logger.error { "#{data} //#{res}" }
        response = [[false, data, res]]
    end

    xmlrpc_response = settings.xmlrpc.methodResponse(true, *response)

    [200, xmlrpc_response]
end
