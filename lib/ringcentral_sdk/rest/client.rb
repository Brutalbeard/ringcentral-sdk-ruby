require 'base64'
require 'faraday'
require 'faraday_middleware'
require 'faraday_middleware/oauth2_refresh'
require 'oauth2'

module RingCentralSdk::REST
  class Client
    ACCESS_TOKEN_TTL  = 600             # 10 minutes
    REFRESH_TOKEN_TTL = 36000           # 10 hours
    REFRESH_TOKEN_TTL_REMEMBER = 604800 # 1 week
    ACCOUNT_PREFIX    = '/account/'
    ACCOUNT_ID        = '~'
    AUTHZ_ENDPOINT    = '/restapi/oauth/authorize'
    TOKEN_ENDPOINT    = '/restapi/oauth/token'
    REVOKE_ENDPOINT   = '/restapi/oauth/revoke'
    API_VERSION       = 'v1.0'
    URL_PREFIX        = '/restapi'
    DEFAULT_LANGUAGE  = 'en-us'

    attr_reader :app_config
    attr_reader :http
    attr_reader :oauth2client
    attr_reader :token
    attr_reader :user_agent
    attr_reader :messages

    attr_reader :instance_headers

    def initialize(app_key='', app_secret='', server_url=RingCentralSdk::RC_SERVER_SANDBOX, opts={})
      init_attributes()
      self.app_config = RingCentralSdk::REST::ConfigApp.new(
        app_key, app_secret, server_url, opts)

      if opts.key?(:username) && opts.key?(:password)
        extension = opts.key?(:extension) ? opts[:extension] : ''
        authorize_password(opts[:username], extension, opts[:password])
      end

      @instance_headers = opts[:headers] || {}

      @messages = RingCentralSdk::REST::Messages.new self
    end

    def app_config=(new_app_config)
      @app_config = new_app_config
      @oauth2client = new_oauth2_client()
    end

    def init_attributes()
      @token = nil
      @http = nil
      @user_agent = get_user_agent()
    end

    def api_version_url()
      return @app_config.server_url + URL_PREFIX + '/' + API_VERSION 
    end

    def create_url(url, add_server=false, add_method=nil, add_token=false)
      built_url = ''
      has_http = !url.index('http://').nil? && !url.index('https://').nil?

      if add_server && ! has_http
        built_url += @app_config.server_url
      end

      if url.index(URL_PREFIX).nil? && ! has_http
        built_url += URL_PREFIX + '/' + API_VERSION + '/'
      end

      if url.index('/') == 0
        if built_url =~ /\/$/
          built_url += url.gsub(/^\//, '')
        else
          built_url += url
        end
      else # no /
        if built_url =~ /\/$/
          built_url += url
        else
          built_url += '/' + url
        end
      end

      return built_url
    end

    def create_urls(urls, add_server=false, add_method=nil, add_token=false)
      unless urls.is_a?(Array)
        raise "URLs is not an array"
      end
      built_urls = []
      urls.each do |url|
        built_urls.push(create_url(url, add_server, add_method, add_token))
      end
      return built_urls
    end

    def authorize_url(opts = {})
      @oauth2client.auth_code.authorize_url(_add_redirect_uri(opts))
    end

    def authorize_code(code, opts = {})
      token = @oauth2client.auth_code.get_token(code, _add_redirect_uri(opts))
      set_token(token)
      return token
    end

    def _add_redirect_uri(opts = {})
      if !opts.key?(:redirect_uri) && @app_config.redirect_url.to_s.length > 0
        opts[:redirect_uri] = @app_config.redirect_url.to_s
      end
      return opts
    end

    def authorize_password(username, extension = '', password = '', remember = false)
      token = @oauth2client.password.get_token(username, password, {
        extension: extension,
        headers: {'Authorization' => 'Basic ' + get_api_key()}})
      set_token(token)
      return token
    end

    def authorize_user(user, remember = false)
      authorize_password(user.username, user.extension, user.password)
    end

    def set_token(token)
      if token.is_a? Hash
        token = OAuth2::AccessToken::from_hash(@oauth2client, token)
      end

      unless token.is_a? OAuth2::AccessToken
        raise "Token is not a OAuth2::AccessToken"
      end

      @token = token

      @http = Faraday.new(url: api_version_url()) do |conn|
        conn.request :oauth2_refresh, @token
        conn.request :json
        conn.request :url_encoded
        conn.headers['User-Agent'] = @user_agent
        if @instance_headers.is_a? Hash 
          @instance_headers.each do |k,v|
            conn.headers[k] = v
          end
        end
        conn.headers['RC-User-Agent'] = @user_agent
        conn.headers['SDK-User-Agent'] = @user_agent
        conn.response :json, content_type: /\bjson$/
        conn.adapter Faraday.default_adapter
      end
    end

    def new_oauth2_client()
      return OAuth2::Client.new(@app_config.key, @app_config.secret,
        site: @app_config.server_url,
        authorize_url: AUTHZ_ENDPOINT,
        token_url: TOKEN_ENDPOINT)
    end

    def set_oauth2_client(client=nil)
      if client.nil?
        @oauth2client = new_oauth2_client()
      elsif client.is_a? OAuth2::Client
        @oauth2client = client
      else
        fail "client is not an OAuth2::Client"
      end
    end

    def get_api_key()
      api_key = (@app_config.key.is_a?(String) && @app_config.secret.is_a?(String)) \
        ? Base64.encode64("#{@app_config.key}:#{@app_config.secret}").gsub(/\s/,'') : ''
      return api_key
    end

    def send_request(request_sdk = {})
      if request_sdk.is_a? Hash
        request_sdk = RingCentralSdk::REST::Request::Simple.new(request_sdk)
      elsif !request_sdk.is_a? RingCentralSdk::REST::Request::Base
        fail 'Request is not a RingCentralSdk::REST::Request::Base'
      end

      method = request_sdk.method.to_s.downcase
      method = 'get' if method.empty?

      res = nil

      case method
      when 'delete'
        res = @http.delete { |req| req = inflate_request(req, request_sdk) }
      when 'get'
        res = @http.get { |req| req = inflate_request(req, request_sdk) }
      when 'post'
        res = @http.post { |req| req = inflate_request(req, request_sdk) }
      when 'put'
        res = @http.put { |req| req = inflate_request(req, request_sdk) }
      else
        fail "method [#{method}] not supported"
      end
      return res
    end

    def inflate_request(req_faraday, req_sdk)
      req_faraday.url req_sdk.url
      req_faraday.body = req_sdk.body if req_sdk.body
      if req_sdk.params.is_a? Hash 
        req_sdk.params.each { |k,v| req_faraday.params[k] = v }
      end
      if req_sdk.headers.is_a? Hash 
        req_sdk.headers.each { |k,v| req_faraday.headers[k] = v }
      end

      ct = req_sdk.content_type
      if !ct.nil? && ct.to_s.length > 0
        req_faraday.headers['Content-Type'] = ct.to_s
      end
      return req_faraday
    end

    def get_user_agent()
      ua = "ringcentral-sdk-ruby/#{RingCentralSdk::VERSION} %s/%s %s" % [
        (RUBY_ENGINE rescue nil or "ruby"),
        RUBY_VERSION,
        RUBY_PLATFORM
      ]
      return ua.strip
    end

    def create_subscription()
      return RingCentralSdk::REST::Subscription.new(self)
    end

    alias_method :authorize, :authorize_password
    alias_method :login, :authorize_password
    private :api_version_url
  end
end
