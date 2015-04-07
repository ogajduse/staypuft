module Staypuft
  class Deployment < ActiveRecord::Base

    # Form step states
    STEP_INACTIVE      = :inactive
    STEP_SETTINGS      = :settings
    STEP_CONFIGURATION = :configuration
    STEP_COMPLETE      = :complete
    STEP_OVERVIEW      = :overview
    STEP_NETWORKING    = :networking

    NEW_NAME_PREFIX = 'uninitialized_'

    # supporting import/export
    EXPORT_PARAMS   = [:amqp_provider, :networking, :layout_name, :platform]
    EXPORT_SERVICES = [:nova, :neutron, :glance, :cinder, :passwords, :ceph]

    attr_accessible :description, :name, :layout_id, :layout,
                    :amqp_provider, :layout_name, :networking, :platform,
                    :custom_repos
    after_save :update_hostgroup_name
    after_validation :check_form_complete

    belongs_to :layout

    # needs to be defined before hostgroup association
    belongs_to :hostgroup, :dependent => :destroy

    has_many :deployment_role_hostgroups, :dependent => :destroy
    has_many :child_hostgroups,
             :through    => :deployment_role_hostgroups,
             :class_name => 'Hostgroup',
             :source     => :hostgroup

    has_many :roles,
             :through => :deployment_role_hostgroups
    has_many :roles_ordered,
             :through => :deployment_role_hostgroups,
             :source  => :role,
             :order   => "#{::Staypuft::DeploymentRoleHostgroup.table_name}.deploy_order"

    has_many :services, :through => :roles
    has_many :hosts, :through => :child_hostgroups

    has_many :subnet_typings, :dependent => :destroy
    has_many :subnet_types, :through => :subnet_typings
    has_many :subnets, :through => :subnet_typings

    validates :name, :presence => true, :uniqueness => true

    validates :layout, :presence => true
    validates :hostgroup, :presence => true

    validate :all_required_subnet_types_associated, :if => Proc.new { |o| o.form_step == STEP_NETWORKING }

    after_validation :check_form_complete
    before_save :update_layout
    after_save :update_based_on_settings

    SCOPES = [[:nova, :@nova_service, NovaService],
              [:neutron, :@neutron_service, NeutronService],
              [:glance, :@glance_service, GlanceService],
              [:cinder, :@cinder_service, CinderService],
              [:passwords, :@passwords, Passwords],
              [:ceph, :@ceph, CephService]]

    SCOPES.each do |name, ivar, scope_class|
      define_method name do
        instance_variable_get ivar or
            instance_variable_set ivar, scope_class.new(self)
      end
      after_save { send(name).run_callbacks :save }
    end

    validates_associated :nova, :if => lambda { |d| d.form_step_is_past_configuration? && d.nova.active? }
    validates_associated :neutron, :if => lambda { |d| d.form_step_is_past_configuration? && d.neutron.active? }
    validates_associated :glance, :if =>  lambda {|d| d.form_step_is_past_configuration? && d.glance.active? }
    validates_associated :cinder, :if =>  lambda {|d| d.form_step_is_past_configuration? && d.cinder.active? }
    validates_associated :passwords

    def initialize(attributes = {}, options = {})
      super({ amqp_provider: AmqpProvider::RABBITMQ,
              layout_name:   LayoutName::NON_HA,
              networking:    Networking::NEUTRON,
              platform:      Platform::RHEL7 }.merge(attributes),
            options)

      self.hostgroup = Hostgroup.new(name: name, parent: Hostgroup.get_base_hostgroup)

      self.nova.set_defaults
      self.neutron.set_defaults
      self.glance.set_defaults
      self.cinder.set_defaults
      self.passwords.set_defaults
      self.ceph.set_defaults
      self.layout = Layout.where(:name       => self.layout_name,
                                 :networking => self.networking).first
    end

    extend AttributeParamStorage

    # Helper method for looking up a Deployment based on a foreman task
    def self.find_by_foreman_task(foreman_task)
      task = ForemanTasks::Lock.where(task_id: foreman_task.id,
                                                     name: :deploy,
                                                     resource_type: 'Staypuft::Deployment').first
      unless task.nil?
        Deployment.find(task.resource_id)
      else
        nil
      end

    end

    # Returns a list of hosts that are currently being deployed.
    def in_progress_hosts(hostgroup)
      return in_progress? ? hostgroup.openstack_hosts : {}
    end

    # Helper method for checking whether this deployment is in progress or not.
    def in_progress?
      ForemanTasks::Lock.locked? self, nil
    end

    def hide_ceph_notification?
      ceph_hostgroup.hosts.empty?
    end

    # Helper method for getting the in progress foreman task for this
    # deployment.
    def task
      in_progress? ? ForemanTasks::Lock.colliding_locks(self, nil).first.task : nil
    end

    # Returns all deployed hosts with no errors (default behaviour).  Set
    # errors=true to return all deployed hosts that have errors
    def deployed_hosts(hostgroup, errors=false)
      in_progress? ? {} : hostgroup.openstack_hosts(errors)
    end

    def progress_summary
      self.in_progress? ? self.task.humanized[:output] : nil
    end

    # Helper method for getting the progress of this deployment
    def progress
      if self.in_progress?
        (self.task.progress * 100).round(1)
      elsif self.deployed?
        100
      else
        0
      end
    end

    def self.param_scope
      'deployment'
    end

    module AmqpProvider
      RABBITMQ = 'rabbitmq'
      QPID     = 'qpid'
      LABELS   = { RABBITMQ => N_('RabbitMQ'), QPID => N_('Qpid') }
      TYPES    = LABELS.keys
      HUMAN    = N_('Messaging Provider')
    end

    module Networking
      NOVA    = 'nova'
      NEUTRON = 'neutron'
      LABELS  = { NEUTRON => N_('Neutron Networking'), NOVA => N_('Nova Network') }
      TYPES   = LABELS.keys
      HUMAN   = N_('Networking')
    end

    module LayoutName
      NON_HA = 'Controller / Compute'
      HA     = 'High Availability Controllers / Compute'
      LABELS = { NON_HA => N_('Controller / Compute'),
                 HA     => N_('High Availability Controllers / Compute') }
      TYPES  = LABELS.keys
      HUMAN  = N_('High Availability')
    end

    module Platform
      RHEL7  = 'rhel7'
      RHEL6  = 'rhel6'
      LABELS = { RHEL7 => N_('Red Hat Enterprise Linux OpenStack Platform 5 with RHEL 7')}
      TYPES  = LABELS.keys
      HUMAN  = N_('Platform')
    end

    param_attr :amqp_provider, :networking, :layout_name, :platform
    validates :amqp_provider, :presence => true, :inclusion => { :in => AmqpProvider::TYPES }
    validates :networking, :presence => true, :inclusion => { :in => Networking::TYPES }
    validates :layout_name, presence: true, inclusion: { in: LayoutName::TYPES }
    validates :platform, presence: true, inclusion: { in: Platform::TYPES }

    class Jail < Safemode::Jail
      allow :amqp_provider, :networking, :layout_name, :platform, :nova_networking?, :neutron_networking?,
        :nova, :neutron, :glance, :cinder, :passwords, :ceph, :ha?, :non_ha?,
        :hide_ceph_notification?, :network_query, :has_custom_repos?, :custom_repos_paths
    end

    # TODO(mtaylor)
    # Use conditional validations to validate the deployment multi-step form.
    # deployment.form_step should be used to check the form step the user is
    # currently on.
    # e.g.
    # validates :name, :presence => true, :if => :form_step_is_configuration?

    scoped_search :on => :name, :complete_value => :true

    def self.available_locks
      [:deploy]
    end

    def services_hostgroup_map
      deployment_role_hostgroups.map do |deployment_role_hostgroup|
        deployment_role_hostgroup.services.reduce({}) do |h, s|
          h.update s => deployment_role_hostgroup.hostgroup
        end
      end.reduce(&:merge)
    end

    def deployed?
      self.hosts.any?(&:open_stack_deployed?)
    end

    def form_step_is_configuration?
      self.form_step.to_sym == Deployment::STEP_CONFIGURATION
    end

    def form_step_is_past_configuration?
      self.form_step_is_configuration? || self.form_complete?
    end

    def form_complete?
      self.form_step.to_sym == Deployment::STEP_COMPLETE
    end

    def ha?
      self.layout_name == LayoutName::HA
    end

    def non_ha?
      self.layout_name == LayoutName::NON_HA
    end

    def nova_networking?
      networking == Networking::NOVA
    end

    def neutron_networking?
      networking == Networking::NEUTRON
    end

    def horizon_url
      if ha?
        "http://#{network_query.get_vip(:horizon_public_vip)}"
      else
        network_query.controller_ips(Staypuft::SubnetType::PUBLIC_API).empty? ? nil : "http://#{network_query.controller_ip(Staypuft::SubnetType::PUBLIC_API)}"
      end
    end

    def controller_hostgroup
      Hostgroup.includes(:deployment_role_hostgroup).
        where(DeploymentRoleHostgroup.table_name => { deployment_id: self,
                                                      role_id:       Staypuft::Role.controller }).
        first
    end

    def unassigned_subnet_types
      self.layout.subnet_types - self.subnet_types
    end

    def unassigned_pxe_default_subnet_types
      self.layout.subnet_types.pxe_defaults - self.subnet_types
    end

    def ceph_hostgroup
      Hostgroup.includes(:deployment_role_hostgroup).
        where(DeploymentRoleHostgroup.table_name => { deployment_id: self,
                                                      role_id:       Staypuft::Role.cephosd }).
        first
    end

    def network_query
      @network_query || NetworkQuery.new(self)
    end

    def has_custom_repos?
      self.custom_repos.present?
    end

    def custom_repos_paths
      self.custom_repos.split("\n")
    end

    private

    def update_layout
      self.layout = Layout.where(:name => layout_name, :networking => networking).first
    end

    def update_based_on_settings
      update_hostgroup_name
      update_operating_system
      update_hostgroup_list
    end

    def all_required_subnet_types_associated
      associated_subnet_types = self.subnet_typings.map(&:subnet_type)
      missing_required = self.layout.subnet_types.required.select { |t| !associated_subnet_types.include?(t) }
      unless missing_required.empty?
        errors.add :base,
                   _("Some required subnet types are missing association of a subnet. Please drag and drop following types: %s") % missing_required.map(&:name).join(', ')
      end
    end

    def update_hostgroup_name
      hostgroup.name = self.name
      hostgroup.save!
    end

    def update_operating_system
      name = Setting[:base_hostgroup].include?('RedHat') ? 'RedHat' : 'CentOS'
      self.hostgroup.operatingsystem = case platform
                                       when Platform::RHEL6
                                         Operatingsystem.where(name: name, major: '6', minor: '5').first
                                       when Platform::RHEL7
                                         Operatingsystem.where(name: name, major: '7').order('minor desc').first
                                       end or
          raise 'missing Operatingsystem'
      self.hostgroup.save!
    end

    # After setting or changing layout, update the set of child hostgroups,
    # adding groups for any roles not already represented, and removing others
    # no longer needed.
    def update_hostgroup_list
      old_deployment_role_hostgroups = deployment_role_hostgroups.to_a
      new_deployment_role_hostgroups = layout.layout_roles.map do |layout_role|
        deployment_role_hostgroup = deployment_role_hostgroups.where(:role_id => layout_role.role).first_or_initialize do |drh|
          drh.hostgroup = Hostgroup.new(name: layout_role.role.name, parent: hostgroup)
        end

        deployment_role_hostgroup.hostgroup.add_puppetclasses_from_resource(layout_role.role)
        layout_role.role.services.each do |service|
          deployment_role_hostgroup.hostgroup.add_puppetclasses_from_resource(service)
        end
        # deployment_role_hostgroup.hostgroup.save!

        deployment_role_hostgroup.deploy_order = layout_role.deploy_order
        deployment_role_hostgroup.save!

        deployment_role_hostgroup
      end

      # delete any prior mappings that remain
      (old_deployment_role_hostgroups - new_deployment_role_hostgroups).each &:destroy
    end

    # Checks to see if the form step was the last in the series.  If so it sets
    # the form_step field to complete.
    def check_form_complete
      self.form_step = Deployment::STEP_COMPLETE if self.form_step.to_sym == Deployment::STEP_CONFIGURATION
    end

  end
end
