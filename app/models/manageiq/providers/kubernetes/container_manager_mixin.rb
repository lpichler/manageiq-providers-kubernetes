require 'openssl'
require 'MiqContainerGroup/MiqContainerGroup'

module ManageIQ::Providers::Kubernetes::ContainerManagerMixin
  extend ActiveSupport::Concern

  DEFAULT_PORT = 6443
  METRICS_ROLES = %w(prometheus hawkular).freeze

  included do
    supports :streaming_refresh do
      unsupported_reason_add(:streaming_refresh, "Streaming refresh not enabled") unless streaming_refresh_enabled?
    end

    def streaming_refresh_enabled?
      Settings.ems_refresh[emstype.to_sym]&.streaming_refresh
    end
  end

  def monitoring_manager_needed?
    connection_configurations.roles.include?(
      ManageIQ::Providers::Kubernetes::MonitoringManagerMixin::ENDPOINT_ROLE.to_s
    )
  end

  def supports_metrics?
    endpoints.where(:role => METRICS_ROLES).exists?
  end

  module ClassMethods
    def params_for_create
      @params_for_create ||= begin
        {
          :fields => [
            {
              :component => 'sub-form',
              :name      => 'endpoints-subform',
              :title     => _('Endpoints'),
              :fields    => [
                :component => 'tabs',
                :name      => 'tabs',
                :fields    => [
                  {
                    :component => 'tab-item',
                    :name      => 'default-tab',
                    :title     => _('Default'),
                    :fields    => [
                      {
                        :component              => 'validate-provider-credentials',
                        :name                   => 'authentications.default.valid',
                        :skipSubmit             => true,
                        :validationDependencies => %w[type],
                        :fields                 => [
                          {
                            :component  => "select-field",
                            :name       => "endpoints.default.security_protocol",
                            :label      => _("Security Protocol"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :options    => [
                              {
                                :label => _("SSL"),
                                :value => "ssl-with-validation"
                              },
                              {
                                :label => _("SSL trusting custom CA"),
                                :value => "ssl-with-validation-custom-ca"
                              },
                              {
                                :label => _("SSL without validation"),
                                :value => "ssl-without-validation",
                              },
                            ]
                          },
                          {
                            :component  => "text-field",
                            :name       => "endpoints.default.hostname",
                            :label      => _("Hostname (or IPv4 or IPv6 address)"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                          },
                          {
                            :component    => "text-field",
                            :name         => "endpoints.default.port",
                            :label        => _("API Port"),
                            :type         => "number",
                            :initialValue => default_port,
                            :isRequired   => true,
                            :validate     => [{:type => "required-validator"}],
                          },
                          {
                            :component  => "textarea-field",
                            :name       => "endpoints.default.certificate_authority",
                            :label      => _("Trusted CA Certificates"),
                            :rows       => 10,
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :condition  => {
                              :when => 'endpoints.default.security_protocol',
                              :is   => 'ssl-with-validation-custom-ca',
                            },
                          },
                          {
                            :component  => "password-field",
                            :name       => "authentications.bearer.auth_key",
                            :label      => "Token",
                            :type       => "password",
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                          },
                        ]
                      }
                    ]
                  },
                  {
                    :component => 'tab-item',
                    :name      => 'metrics-tab',
                    :title     => _('Metrics'),
                    :fields    => [
                      {
                        :component    => 'protocol-selector',
                        :name         => 'metrics_selection',
                        :skipSubmit   => true,
                        :initialValue => 'none',
                        :label        => _('Type'),
                        :options      => [
                          {
                            :label => _('Disabled'),
                            :value => 'none',
                          },
                          {
                            :label => _('Hawkular'),
                            :value => 'hawkular',
                            :pivot => 'endpoints.hawkular.hostname',
                          },
                          {
                            :label => _('Prometheus'),
                            :value => 'prometheus',
                            :pivot => 'endpoints.prometheus.hostname',
                          },
                        ],
                      },
                      {
                        :component              => 'validate-provider-credentials',
                        :name                   => "authentications.hawkular.valid",
                        :skipSubmit             => true,
                        :validationDependencies => ['type', "metrics_selection", "authentications.bearer.auth_key"],
                        :condition              => {
                          :when => "metrics_selection",
                          :is   => 'hawkular',
                        },
                        :fields                 => [
                          {
                            :component  => "select-field",
                            :name       => "endpoints.hawkular.security_protocol",
                            :label      => _("Security Protocol"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :options    => [
                              {
                                :label => _("SSL"),
                                :value => "ssl-with-validation"
                              },
                              {
                                :label => _("SSL trusting custom CA"),
                                :value => "ssl-with-validation-custom-ca",
                              },
                              {
                                :label => _("SSL without validation"),
                                :value => "ssl-without-validation",
                              },
                            ]
                          },
                          {
                            :component  => "text-field",
                            :name       => "endpoints.hawkular.hostname",
                            :label      => _("Hostname (or IPv4 or IPv6 address)"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :inputAddon => {
                              :after => {
                                :fields => [
                                  {
                                    :component => 'input-addon-button-group',
                                    :name      => 'detect-hawkular-group',
                                    :fields    => [
                                      {
                                        :component    => 'detect-button',
                                        :name         => 'detect-hawkular-button',
                                        :label        => _('Detect'),
                                        :dependencies => [
                                          'endpoints.default.hostname',
                                          'endpoints.default.port',
                                          'endpoints.default.security_protocol',
                                          'endpoints.default.certificate_authority',
                                          'authentications.bearer.auth_key',
                                        ],
                                        :target       => 'endpoints.hawkular',
                                      },
                                    ],
                                  }
                                ],
                              },
                            },
                          },
                          {
                            :component    => "text-field",
                            :name         => "endpoints.hawkular.port",
                            :label        => _("API Port"),
                            :type         => "number",
                            :initialValue => 443,
                            :isRequired   => true,
                            :validate     => [{:type => "required-validator"}],
                          },
                          {
                            :component  => "textarea-field",
                            :name       => "endpoints.hawkular.certificate_authority",
                            :label      => _("Trusted CA Certificates"),
                            :rows       => 10,
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :condition  => {
                              :when => 'endpoints.hawkular.security_protocol',
                              :is   => 'ssl-with-validation-custom-ca',
                            },
                          },
                        ]
                      },
                      {
                        :component              => 'validate-provider-credentials',
                        :name                   => "authentications.prometheus.valid",
                        :skipSubmit             => true,
                        :validationDependencies => ['type', "metrics_selection", "authentications.bearer.auth_key"],
                        :condition              => {
                          :when => "metrics_selection",
                          :is   => 'prometheus',
                        },
                        :fields                 => [
                          {
                            :component  => "select-field",
                            :name       => "endpoints.prometheus.security_protocol",
                            :label      => _("Security Protocol"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :options    => [
                              {
                                :label => _("SSL"),
                                :value => "ssl-with-validation"
                              },
                              {
                                :label => _("SSL trusting custom CA"),
                                :value => "ssl-with-validation-custom-ca"
                              },
                              {
                                :label => _("SSL without validation"),
                                :value => "ssl-without-validation"
                              },
                            ]
                          },
                          {
                            :component  => "text-field",
                            :name       => "endpoints.prometheus.hostname",
                            :label      => _("Hostname (or IPv4 or IPv6 address)"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :inputAddon => {
                              :after => {
                                :fields => [
                                  {
                                    :component => 'input-addon-button-group',
                                    :name      => 'detect-prometheus-group',
                                    :fields    => [
                                      {
                                        :component    => 'detect-button',
                                        :name         => 'detect-prometheus-button',
                                        :label        => _('Detect'),
                                        :dependencies => [
                                          'endpoints.default.hostname',
                                          'endpoints.default.port',
                                          'endpoints.default.security_protocol',
                                          'endpoints.default.certificate_authority',
                                          'authentications.bearer.auth_key',
                                        ],
                                        :target       => 'endpoints.prometheus',
                                      },
                                    ],
                                  }
                                ],
                              },
                            },
                          },
                          {
                            :component    => "text-field",
                            :name         => "endpoints.prometheus.port",
                            :label        => _("API Port"),
                            :type         => "number",
                            :initialValue => 443,
                            :isRequired   => true,
                            :validate     => [{:type => "required-validator"}],
                          },
                          {
                            :component  => "textarea-field",
                            :name       => "endpoints.prometheus.certificate_authority",
                            :label      => _("Trusted CA Certificates"),
                            :rows       => 10,
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :condition  => {
                              :when => 'endpoints.prometheus.security_protocol',
                              :is   => 'ssl-with-validation-custom-ca',
                            },
                          },
                        ]
                      }
                    ]
                  },
                  {
                    :component => 'tab-item',
                    :name      => 'alerts-tab',
                    :title     => _('Alerts'),
                    :fields    => [
                      {
                        :component    => 'protocol-selector',
                        :name         => 'alerts_selection',
                        :skipSubmit   => true,
                        :initialValue => 'none',
                        :label        => _('Type'),
                        :options      => [
                          {
                            :label => _('Disabled'),
                            :value => 'none',
                          },
                          {
                            :label => _('Prometheus'),
                            :value => 'prometheus_alerts',
                            :pivot => 'endpoints.prometheus_alerts.hostname',
                          },
                        ],
                      },
                      {
                        :component              => 'validate-provider-credentials',
                        :name                   => "authentications.prometheus_alerts.valid",
                        :skipSubmit             => true,
                        :validationDependencies => ['type', "alerts_selection", "authentications.bearer.auth_key"],
                        :condition              => {
                          :when => "alerts_selection",
                          :is   => 'prometheus_alerts',
                        },
                        :fields                 => [
                          {
                            :component  => "select-field",
                            :name       => "endpoints.prometheus_alerts.security_protocol",
                            :label      => _("Security Protocol"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :options    => [
                              {
                                :label => _("SSL"),
                                :value => "ssl-with-validation"
                              },
                              {
                                :label => _("SSL trusting custom CA"),
                                :value => "ssl-with-validation-custom-ca"
                              },
                              {
                                :label => _("SSL without validation"),
                                :value => "ssl-without-validation"
                              },
                            ]
                          },
                          {
                            :component  => "text-field",
                            :name       => "endpoints.prometheus_alerts.hostname",
                            :label      => _("Hostname (or IPv4 or IPv6 address)"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :inputAddon => {
                              :after => {
                                :fields => [
                                  {
                                    :component => 'input-addon-button-group',
                                    :name      => 'detect-prometheus_alerts-group',
                                    :fields    => [
                                      {
                                        :component    => 'detect-button',
                                        :name         => 'detect-prometheus_alerts-button',
                                        :label        => _('Detect'),
                                        :dependencies => [
                                          'endpoints.default.hostname',
                                          'endpoints.default.port',
                                          'endpoints.default.security_protocol',
                                          'endpoints.default.certificate_authority',
                                          'authentications.bearer.auth_key',
                                        ],
                                        :target       => 'endpoints.prometheus_alerts',
                                      },
                                    ],
                                  }
                                ],
                              },
                            },
                          },
                          {
                            :component    => "text-field",
                            :name         => "endpoints.prometheus_alerts.port",
                            :label        => _("API Port"),
                            :type         => "number",
                            :initialValue => 443,
                            :isRequired   => true,
                            :validate     => [{:type => "required-validator"}],
                          },
                          {
                            :component  => "textarea-field",
                            :name       => "endpoints.prometheus_alerts.certificate_authority",
                            :label      => _("Trusted CA Certificates"),
                            :rows       => 10,
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :condition  => {
                              :when => 'endpoints.prometheus_alerts.security_protocol',
                              :is   => 'ssl-with-validation-custom-ca',
                            },
                          },
                        ]
                      }
                    ]
                  },
                  {
                    :component => 'tab-item',
                    :name      => 'virtualization-tab',
                    :title     => _('Virtualization'),
                    :fields    => [
                      {
                        :component    => 'protocol-selector',
                        :name         => 'virtualization_selection',
                        :skipSubmit   => true,
                        :initialValue => 'none',
                        :label        => _('Type'),
                        :options      => [
                          {
                            :label => _('Disabled'),
                            :value => 'none',
                          },
                          {
                            :label => _('KubeVirt'),
                            :value => 'kubevirt',
                            :pivot => 'endpoints.kubevirt.hostname',
                          },
                        ],
                      },
                      {
                        :component              => 'validate-provider-credentials',
                        :name                   => 'endpoints.virtualization.valid',
                        :skipSubmit             => true,
                        :validationDependencies => %w[type virtualization_selection],
                        :condition              => {
                          :when => 'virtualization_selection',
                          :is   => 'kubevirt',
                        },
                        :fields                 => [
                          {
                            :component  => "select-field",
                            :name       => "endpoints.kubevirt.security_protocol",
                            :label      => _("Security Protocol"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :options    => [
                              {
                                :label => _("SSL"),
                                :value => "ssl-with-validation"
                              },
                              {
                                :label => _("SSL trusting custom CA"),
                                :value => "ssl-with-validation-custom-ca"
                              },
                              {
                                :label => _("SSL without validation"),
                                :value => "ssl-without-validation"
                              },
                            ]
                          },
                          {
                            :component  => "text-field",
                            :name       => "endpoints.kubevirt.hostname",
                            :label      => _("Hostname (or IPv4 or IPv6 address)"),
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :inputAddon => {
                              :after => {
                                :fields => [
                                  {
                                    :component => 'input-addon-button-group',
                                    :name      => 'detect-kubevirt-group',
                                    :fields    => [
                                      {
                                        :component    => 'detect-button',
                                        :name         => 'detect-kubevirt-button',
                                        :label        => _('Detect'),
                                        :dependencies => [
                                          'endpoints.default.hostname',
                                          'endpoints.default.port',
                                          'endpoints.default.security_protocol',
                                          'endpoints.default.certificate_authority',
                                          'authentications.bearer.auth_key',
                                        ],
                                        :target       => 'endpoints.kubevirt',
                                      },
                                    ],
                                  }
                                ],
                              },
                            },
                          },
                          {
                            :component    => "text-field",
                            :name         => "endpoints.kubevirt.port",
                            :label        => _("API Port"),
                            :type         => "number",
                            :initialValue => default_port,
                            :isRequired   => true,
                            :validate     => [{:type => "required-validator"}],
                          },
                          {
                            :component  => "textarea-field",
                            :name       => "endpoints.kubevirt.certificate_authority",
                            :label      => _("Trusted CA Certificates"),
                            :rows       => 10,
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                            :condition  => {
                              :when => 'endpoints.kubevirt.security_protocol',
                              :is   => 'ssl-with-validation-custom-ca',
                            },
                          },
                          {
                            :component  => "password-field",
                            :name       => "authentications.kubevirt.auth_key",
                            :label      => "Token",
                            :type       => "password",
                            :isRequired => true,
                            :validate   => [{:type => "required-validator"}],
                          },
                        ]
                      }
                    ]
                  }
                ]
              ]
            },
            {
              :component => 'sub-form',
              :name      => 'settings-subform',
              :title     => _('Settings'),
              :fields    => [
                :component => 'tabs',
                :name      => 'tabs',
                :fields    => [
                  {
                    :component => 'tab-item',
                    :name      => 'proxy-tab',
                    :title     => _('Proxy'),
                    :fields    => [
                      {
                        :component   => 'text-field',
                        :name        => 'options.proxy_settings.http_proxy',
                        :label       => _('HTTP Proxy'),
                        :helperText  => _('HTTP Proxy to connect ManageIQ to the provider. example: http://user:password@my_http_proxy'),
                        :placeholder => VMDB::Util.http_proxy_uri,
                      }
                    ],
                  },
                  {
                    :component => 'tab-item',
                    :name      => 'image-inspector-tab',
                    :title     => _('Image-Inspector'),
                    :fields    => [
                      {
                        :component  => 'text-field',
                        :name       => 'options.image_inspector_options.http_proxy',
                        :label      => _('HTTP Proxy'),
                        :helperText => _('HTTP Proxy to connect image inspector pods to the internet. example: http://user:password@my_http_proxy')
                      },
                      {
                        :component  => 'text-field',
                        :name       => 'options.image_inspector_options.https_proxy',
                        :label      => _('HTTPS Proxy'),
                        :helperText => _('HTTPS Proxy to connect image inspector pods to the internet. example: https://user:password@my_https_proxy')
                      },
                      {
                        :component  => 'text-field',
                        :name       => 'options.image_inspector_options.no_proxy',
                        :label      => _('No Proxy'),
                        :helperText => _("No Proxy lists urls that should'nt be sent to any proxy. example: my_file_server.org")
                      },
                      {
                        :component   => 'text-field',
                        :name        => 'options.image_inspector_options.repository',
                        :label       => _('Repository'),
                        :helperText  => _('Image-Inspector Repository. example: openshift/image-inspector'),
                        :placeholder => ::Settings.ems.ems_kubernetes.image_inspector_repository,
                      },
                      {
                        :component   => 'text-field',
                        :name        => 'options.image_inspector_options.registry',
                        :label       => _('Registry'),
                        :helperText  => _('Registry to provide the image inspector repository. example: docker.io'),
                        :placeholder => ::Settings.ems.ems_kubernetes.image_inspector_registry,
                      },
                      {
                        :component   => 'text-field',
                        :name        => 'options.image_inspector_options.image_tag',
                        :label       => _('Image Tag'),
                        :helperText  => _('Image-Inspector image tag. example: 2.1'),
                        :placeholder => ManageIQ::Providers::Kubernetes::ContainerManager::Scanning::Job::INSPECTOR_IMAGE_TAG,
                      },
                      {
                        :component   => 'text-field',
                        :name        => 'options.image_inspector_options.cve_url',
                        :label       => _('CVE Location'),
                        :helperText  => _('Enables defining a URL path prefix for XCCDF file instead of accessing the default location.
  example: http://my_file_server.org:3333/xccdf_files/
  Expecting to find com.redhat.rhsa-RHEL7.ds.xml.bz2 file there.'),
                        :placeholder => ::Settings.ems.ems_kubernetes.image_inspector_cve_url,
                      },
                    ],
                  },
                ],
              ],
            },
          ],
        }.freeze
      end
    end

    def verify_credentials(args)
      endpoint_name = args.dig("endpoints").keys.first
      endpoint = args.dig("endpoints", endpoint_name)

      token = args.dig("authentications", "bearer", "auth_key") || args.dig("authentications", "kubevirt", "auth_key")
      token = MiqPassword.try_decrypt(token)
      token ||= find(args["id"]).authentication_token(endpoint_name == 'kubevirt' ? 'kubevirt' : 'bearer') if args["id"]

      hostname, port = endpoint&.values_at("hostname", "port")

      options = {
        :bearer      => token,
        :ssl_options => {
          :verify_ssl => endpoint&.dig("security_protocol") == 'ssl-without-validation' ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER,
          :ca_file    => endpoint&.dig("certificate_authority")
        }
      }

      case endpoint_name
      when 'default', 'kubevirt' # this also (partially) validates kubevirt
        !!raw_connect(hostname, port, options)
      when 'prometheus', 'prometheus_alerts', 'hawkular'
        # TODO: implement validation calls for these endpoint types
        return true
      else
        # TODO: maybe we need an error message here
        return false
      end
    end

    def create_from_params(params, endpoints, authentications)
      bearer = authentications.find { |authentication| authentication['authtype'] == 'bearer' }

      # Replicate the bearer authentication for all endpoints, except for default and kubevirt
      endpoints.each do |endpoint|
        next if %w[default kubevirt].include?(endpoint['role'])

        authentications << bearer.merge('authtype' => endpoint['role'])
      end

      super(params, endpoints, authentications)
    end

    def raw_api_endpoint(hostname, port, path = '')
      URI::HTTPS.build(:host => hostname, :port => port.presence.try(:to_i), :path => path)
    end

    def kubernetes_connect(hostname, port, options)
      require 'kubeclient'

      conn = Kubeclient::Client.new(
        raw_api_endpoint(hostname, port, options[:path]),
        options[:version] || kubernetes_version,
        :ssl_options    => Kubeclient::Client::DEFAULT_SSL_OPTIONS.merge(options[:ssl_options] || {}),
        :auth_options   => kubernetes_auth_options(options),
        :http_proxy_uri => options[:http_proxy] || VMDB::Util.http_proxy_uri,
        :timeouts       => {
          :open => Settings.ems.ems_kubernetes.open_timeout.to_f_with_method,
          :read => Settings.ems.ems_kubernetes.read_timeout.to_f_with_method
        }
      )

      # Test the API endpoint at connect time to prevent exception being raised
      # on first method call
      conn.discover

      conn
    end

    def kubernetes_auth_options(options)
      auth_options = {}
      if options[:username] && options[:password]
        auth_options[:username] = options[:username]
        auth_options[:password] = options[:password]
      end
      auth_options[:bearer_token] = options[:bearer] if options[:bearer]
      auth_options
    end

    def kubernetes_version
      'v1'
    end

    def kubernetes_service_catalog_connect(hostname, port, options)
      options = {:path => '/apis/servicecatalog.k8s.io', :version => service_catalog_api_version}.merge(options)
      kubernetes_connect(hostname, port, options)
    end

    def service_catalog_api_version
      'v1beta1'
    end
  end

  PERF_ROLLUP_CHILDREN = [:container_nodes]

  def edit_with_params(params, endpoints, authentications)
    bearer = authentications.find { |authentication| authentication['authtype'] == 'bearer' }
    kubevirt = authentications.find { |authentication| authentication['authtype'] == 'kubevirt' }
    # As the authentication is token-only, no data is being submitted if there's no change as we never send
    # down the password to the client. This would cause the deletion of the untouched authentications in the
    # super() below. In order to prevent this, the authentications are set to a dummy value if the related
    # endpoint exists among the submitted data.
    endpoints.each do |endpoint|
      case endpoint['role']
      when 'default' # The default endpoint is paired with the bearer authentication
        authentications << {'authtype' => 'bearer'} unless bearer
      when 'kubevirt' # Kubevirt has its own authentication, no need for replication
        authentications << {'authtype' => 'kubevirt'} unless kubevirt
      else # Replicate the bearer authentication for any other endpoints
        authentications << {'authtype' => endpoint['role']}.reverse_merge(bearer || {:auth_key => authentication_token})
      end
    end

    super(params, endpoints, authentications)
  end

  def verify_hawkular_credentials
    client = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularClient.new(self)
    client.hawkular_try_connect
  end

  def verify_prometheus_credentials
    client = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClient.new(self)
    client.prometheus_try_connect
  end

  def verify_prometheus_alerts_credentials
    ensure_monitoring_manager
    monitoring_manager.verify_credentials
  end

  def verify_kubevirt_credentials
    ensure_infra_manager
    options = {
      :token => authentication_token(:kubevirt),
    }
    infra_manager.verify_credentials(:kubevirt, options)
    infra_manager.verify_virt_supported(options)
  end

  # UI methods for determining availability of fields
  def supports_port?
    true
  end

  def supports_security_protocol?
    true
  end

  def api_endpoint
    self.class.raw_api_endpoint(hostname, port)
  end

  def verify_ssl_mode(endpoint = default_endpoint)
    return OpenSSL::SSL::VERIFY_PEER if endpoint.nil? # secure by default

    case endpoint.security_protocol
    when nil, ''
      # Previously providers didn't set security_protocol, defaulted to
      # verify_ssl == 1 (VERIFY_PEER) which wasn't enforced but now is.
      # However, if they explicitly set verify_ssl == 0, we'll respect that.
      endpoint.verify_ssl? ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    when 'ssl-without-validation'
      OpenSSL::SSL::VERIFY_NONE
    else # 'ssl-with-validation', 'ssl-with-validation-custom-ca', secure by default with unexpected values.
      OpenSSL::SSL::VERIFY_PEER
    end
  end

  def ssl_cert_store(endpoint = default_endpoint)
    # Given missing (nil) endpoint, return nil meaning use system CA bundle
    endpoint.try(:ssl_cert_store)
  end

  def connect(options = {})
    effective_options = connect_options(options)

    self.class.raw_connect(effective_options[:hostname], effective_options[:port], effective_options)
  end

  def connect_options(options = {})
    options.merge(
      :hostname    => options[:hostname] || address,
      :port        => options[:port] || port,
      :user        => options[:user] || authentication_userid(options[:auth_type]),
      :pass        => options[:pass] || authentication_password(options[:auth_type]),
      :bearer      => options[:bearer] || authentication_token(options[:auth_type] || 'bearer'),
      :http_proxy  => self.options ? self.options.fetch_path(:proxy_settings, :http_proxy) : nil,
      :ssl_options => options[:ssl_options] || {
        :verify_ssl => verify_ssl_mode,
        :cert_store => ssl_cert_store
      }
    )
  end

  def authentications_to_validate
    at = [:bearer]
    at << :hawkular if has_authentication_type?(:hawkular)
    at << :prometheus if has_authentication_type?(:prometheus)
    at << :prometheus_alerts if has_authentication_type?(:prometheus_alerts)
    at << :kubevirt if has_authentication_type?(:kubevirt)
    at
  end

  def required_credential_fields(_type)
    [:auth_key]
  end

  def supported_auth_attributes
    %w(userid password auth_key)
  end

  def verify_credentials(auth_type = nil, options = {})
    options = options.merge(:auth_type => auth_type)
    if options[:auth_type].to_s == "hawkular"
      verify_hawkular_credentials
    elsif options[:auth_type].to_s == "prometheus"
      verify_prometheus_credentials
    elsif options[:auth_type].to_s == "prometheus_alerts"
      verify_prometheus_alerts_credentials
    elsif options[:auth_type].to_s == "kubevirt"
      verify_kubevirt_credentials
    else
      with_provider_connection(options, &:api_valid?)
    end
  rescue SocketError,
         Errno::ECONNREFUSED,
         RestClient::ResourceNotFound,
         RestClient::InternalServerError => err
    raise MiqException::MiqUnreachableError, err.message, err.backtrace
  rescue RestClient::Unauthorized   => err
    raise MiqException::MiqInvalidCredentialsError, err.message, err.backtrace
  end

  def ensure_authentications_record
    return if authentications.present?
    update_authentication(:default => {:userid => "_", :save => false})
  end

  def supported_auth_types
    %w(default password bearer hawkular prometheus prometheus_alerts kubevirt)
  end

  def supports_authentication?(authtype)
    supported_auth_types.include?(authtype.to_s)
  end

  def default_authentication_type
    :bearer
  end

  def scan_job_create(entity, userid)
    check_policy_prevent(:request_containerimage_scan, entity, userid, :raw_scan_job_create)
  end

  def raw_scan_job_create(target_class, target_id = nil, userid = nil, target_name = nil)
    raise MiqException::Error, _("target_class must be a class not an instance") if target_class.kind_of?(ContainerImage)
    ManageIQ::Providers::Kubernetes::ContainerManager::Scanning::Job.create_job(
      :userid          => userid,
      :name            => "Container Image Analysis: '#{target_name}'",
      :target_class    => target_class,
      :target_id       => target_id,
      :zone            => my_zone,
      :miq_server_host => MiqServer.my_server.hostname,
      :miq_server_guid => MiqServer.my_server.guid,
      :ems_id          => id,
    )
  end

  # policy_event: the event sent to automate for policy resolution
  # cb_method:    the MiqQueue callback method along with the parameters that is called
  #               when automate process is done and the event is not prevented to proceed by policy
  def check_policy_prevent(policy_event, event_target, userid, cb_method)
    cb = {
      :class_name  => self.class.to_s,
      :instance_id => id,
      :method_name => :check_policy_prevent_callback,
      :args        => [cb_method, event_target.class.name, event_target.id, userid, event_target.name],
      :server_guid => MiqServer.my_guid
    }
    enforce_policy(event_target, policy_event, {}, { :miq_callback => cb }) unless policy_event.nil?
  end

  def check_policy_prevent_callback(*action, _status, _message, result)
    prevented = false
    if result.kind_of?(MiqAeEngine::MiqAeWorkspaceRuntime)

      event = result.get_obj_from_path("/")['event_stream']
      data  = event.attributes["full_data"]
      prevented = data.fetch_path(:policy, :prevented) if data
    end
    prevented ? _log.info(event.attributes["message"].to_s) : send(*action)
  end

  def enforce_policy(event_target, event, inputs = {}, options = {})
    MiqEvent.raise_evm_event(event_target, event, inputs, options)
  end

  SCAN_CONTENT_PATH = '/api/v1/content'

  def scan_entity_create(scan_data)
    client = ext_management_system.connect(:service => 'kubernetes')
    pod_proxy = client.proxy_url(:pod,
                                 scan_data[:pod_name],
                                 scan_data[:pod_port],
                                 scan_data[:pod_namespace])
    nethttp_options = {
      :use_ssl     => true,
      :verify_mode => verify_ssl_mode,
      :cert_store  => ssl_cert_store,
    }
    MiqContainerGroup.new(pod_proxy + SCAN_CONTENT_PATH,
                          nethttp_options,
                          client.headers.stringify_keys,
                          scan_data[:guest_os])
  end

  def annotate(provider_entity_name, ems_indentifier, annotations, container_project_name = nil)
    with_provider_connection do |conn|
      conn.send(
        "patch_#{provider_entity_name}".to_sym,
        ems_indentifier,
        {"metadata" => {"annotations" => annotations}},
        container_project_name # nil is ok for non namespaced entities (e.g images)
      )
    end
  end

  def evaluate_alert(_alert_id, _event)
    # currently only EmsEvents from Prometheus are tested for node alerts,
    # and these should automatically be translated to alerts.
    true
  end

  def queue_metrics_capture
    self.perf_capture_object.perf_capture_all_queue
  end
end
