module Staypuft
  class NetworkQuery

    VIP_NAMES = {
      :ceilometer_admin_vip   => Staypuft::SubnetType::ADMIN_API,
      :ceilometer_private_vip => Staypuft::SubnetType::MANAGEMENT,
      :ceilometer_public_vip  => Staypuft::SubnetType::PUBLIC_API,
      :cinder_admin_vip       => Staypuft::SubnetType::ADMIN_API,
      :cinder_private_vip     => Staypuft::SubnetType::MANAGEMENT,
      :cinder_public_vip      => Staypuft::SubnetType::PUBLIC_API,
      :db_vip                 => Staypuft::SubnetType::MANAGEMENT,
      :glance_admin_vip       => Staypuft::SubnetType::ADMIN_API,
      :glance_private_vip     => Staypuft::SubnetType::MANAGEMENT,
      :glance_public_vip      => Staypuft::SubnetType::PUBLIC_API,
      :heat_admin_vip         => Staypuft::SubnetType::ADMIN_API,
      :heat_private_vip       => Staypuft::SubnetType::MANAGEMENT,
      :heat_public_vip        => Staypuft::SubnetType::PUBLIC_API,
      :heat_cfn_admin_vip     => Staypuft::SubnetType::ADMIN_API,
      :heat_cfn_private_vip   => Staypuft::SubnetType::MANAGEMENT,
      :heat_cfn_public_vip    => Staypuft::SubnetType::PUBLIC_API,
      :horizon_admin_vip      => Staypuft::SubnetType::ADMIN_API,
      :horizon_private_vip    => Staypuft::SubnetType::MANAGEMENT,
      :horizon_public_vip     => Staypuft::SubnetType::PUBLIC_API,
      :keystone_admin_vip     => Staypuft::SubnetType::ADMIN_API,
      :keystone_private_vip   => Staypuft::SubnetType::MANAGEMENT,
      :keystone_public_vip    => Staypuft::SubnetType::PUBLIC_API,
      :loadbalancer_vip       => Staypuft::SubnetType::PUBLIC_API,
      :neutron_admin_vip      => Staypuft::SubnetType::ADMIN_API,
      :neutron_private_vip    => Staypuft::SubnetType::MANAGEMENT,
      :neutron_public_vip     => Staypuft::SubnetType::PUBLIC_API,
      :nova_admin_vip         => Staypuft::SubnetType::ADMIN_API,
      :nova_private_vip       => Staypuft::SubnetType::MANAGEMENT,
      :nova_public_vip        => Staypuft::SubnetType::PUBLIC_API,
      :amqp_vip               => Staypuft::SubnetType::MANAGEMENT,
      :swift_public_vip       => Staypuft::SubnetType::PUBLIC_API,
      :keystone_private_vip   => Staypuft::SubnetType::MANAGEMENT
    }
    COUNT     = VIP_NAMES.size

    def initialize(deployment, host=nil)
      @deployment = deployment
      @host       = host
    end

    def ip_for_host(subnet_type_name, host=@host)
      interface_hash_for_host(subnet_type_name, host)[:ip]
    end

    def interface_for_host(subnet_type_name, host=@host)
      interface_hash_for_host(subnet_type_name, host)[:interface]
    end

    def network_address_for_host(subnet_type_name, host=@host)
      subnet = subnet_for_host(subnet_type_name, host)
      subnet.network_address if subnet
    end

    def subnet_for_host(subnet_type_name, host=@host)
      interface_hash_for_host(subnet_type_name, host)[:subnet]
    end

    def interfaces_for_tenant_subnet(host=@host)
      interface_hash = interface_hash_for_host(
        Staypuft::SubnetType::TENANT, host)
      return [] if interface_hash.empty?
      subnet = interface_hash[:subnet]
      top_level_interface = host.interfaces.where(
        identifier: interface_hash[:interface]).first
      interfaces = [top_level_interface.identifier]
      if subnet && subnet.has_vlanid?
        next_interface = host.interfaces.where(identifier:
          top_level_interface.attached_to).first
        interfaces << next_interface.identifier
        if next_interface.is_a? Nic::Bond
          interfaces << next_interface.attached_devices_identifiers
        end
      end
      interfaces.flatten
    end

    def tenant_interface?(interface, host=@host)
      interfaces_for_tenant_subnet(host).include?(interface)
    end

    def mtu_for_tenant_subnet
      mtu = @deployment.neutron_networking? ? @deployment.neutron.network_device_mtu : @deployment.nova.network_device_mtu
    end

    def tenant_subnet?(subnet, host=@host)
      subnet == subnet_for_host(Staypuft::SubnetType::TENANT, host)
    end

    def gateway_subnet(host=@host)
      gateway_hash_for_host(host)[:subnet]
    end

    def gateway_interface(host=@host)
      gateway_hash_for_host(host)[:interface]
    end

    def gateway_interface_mac(host=@host)
      gateway_hash_for_host(host)[:mac]
    end

    def controllers
      @controllers ||= @deployment.controller_hostgroup.hosts.order(:id)
    end

    def controller_ips(subnet_type_name)
      controllers.map { |controller| ip_for_host(subnet_type_name, controller) }
    end

    def controller_fqdns
      controllers.map &:fqdn
    end

    def controller_shortnames
      controllers.map &:shortname
    end

    def controller_lb_backend_shortnames
      controllers.map do |controller|
        "lb-backend-"+controller.shortname
      end
    end

    def controller_pcmk_shortnames
      controllers.map do |controller|
        "pcmk-"+controller.shortname
      end
    end

    def get_vip(vip_name)
      if VIP_NAMES[vip_name]
        interface = @deployment.vip_nics.where(:tag => vip_name).first
        interface.ip if interface
      end
    end

    class Jail < Safemode::Jail
      allow :ip_for_host, :interface_for_host, :network_address_for_host,
            :controller_ip, :controller_ips, :controller_fqdns, :get_vip, :controller_pcmk_shortnames,
            :subnet_for_host, :gateway_subnet, :gateway_interface, :gateway_interface_mac,
            :tenant_subnet?, :mtu_for_tenant_subnet, :controller_lb_backend_shortnames,
            :interfaces_for_tenant_subnet, :tenant_interface?
    end

    private
    def interface_hash_for_host(subnet_type_name, host)
      if host.nil?
        raise ArgumentError, "no host specified"
      end

      subnet_type = @deployment.layout.subnet_types.where(:name=> subnet_type_name).first

      # raise error if no subnet with this name is assigned to this layout
      if subnet_type.nil?
        raise ArgumentError, "Invalid subnet type  '#{subnet_type_name}' for layout of this deployment #{@deployment.name}"
      end

      subnet_typing = @deployment.subnet_typings.where(:subnet_type_id => subnet_type.id).first
      # if this subnet type isn't assigned to a subnet for this deployment, return nil
      return {} if subnet_typing.nil?
      subnet = subnet_typing.subnet

      secondary_iface = host.interfaces.where(:subnet_id => subnet.id).first
      # check for primary interface
      if (host.subnet_id == subnet.id)
        {:subnet => host.subnet, :ip => host.ip,
         :interface => host.primary_interface, :mac =>  host.mac }
      elsif !secondary_iface.nil?
        {:subnet => secondary_iface.subnet, :ip => secondary_iface.ip,
         :interface => secondary_iface.identifier, :mac =>  secondary_iface.mac }
      else
        {}
      end
    end

    def gateway_hash_for_host(host)
      gateway_hash = interface_hash_for_host(Staypuft::SubnetType::PUBLIC_API, host)
      gateway_hash = interface_hash_for_host(Staypuft::SubnetType::PXE, host) unless gateway_hash[:subnet]
      gateway_hash = interface_hash_for_host(Staypuft::SubnetType::EXTERNAL, host) if Staypuft::Role.compute.any? { |r| r.name == host.hostgroup.name } && host.deployment.nova_networking?
      gateway_hash
    end
  end
end
