module Staypuft
  module DeploymentsHelper
    def deployment_wizard(step)
      wizard_header(
          step,
          _("Deployment Settings"),
          _("Network Configuration"),
          _("Services Overview"),
          _("Services Configuration")
      )
    end

    def is_new
      @deployment.name.empty?
    end

    def alert_if_deployed
      if @deployment.deployed?
        (alert :class => 'alert-warning',
               :text  => _('Machines are already deployed with this configuration. Changing the configuration parameters ' +
                               'is unsupported and may result in an unusable configuration. <br/>Please proceed with caution.'),
               :close => false).html_safe
      end
    end

    def host_label(host)
      case host
      when Host::Managed
        style ="label-info"
        short = s_("Managed|M")
        label = _('Known Host')
        path  = hash_for_host_path(host)
      when Host::Discovered
        style           ="label-default"
        short           = s_("Discovered|D")
        label           = _('Discovered Host')
        path            = hash_for_discovered_host_path(host)
      else
        style = 'label-warning'
        short = s_("Error|E")
        path  = '#'
        label = _('Unknown Host')
      end

      content_tag(:span, short,
                  { :rel                   => "twipsy",
                    :class                 => "label label-light " + style,
                    :"data-original-title" => _(label) }) + link_to(trunc("  #{host}", 32), path)
    end

    def host_nics(host)
      host.interfaces_identifiers.compact.sort.join(tag(:br)).html_safe
    end

    def host_nics_with_subnets(host)
      nics_list = ""
      host.interfaces_identifiers_with_subnets.each do |nic_plus_subnet|
        nics_list += nic_plus_subnet[0] + " (#{nic_plus_subnet[1]})" + tag(:br)
      end
      nics_list.html_safe
    end

    def host_disks(host)
      hosts_facts = FactValue.joins(:fact_name).where(host_id: host.id)
      host.blockdevices.collect do |blockdevice|
        disk_size = hosts_facts.
            where(fact_names: { name: 'blockdevice_#{blockdevice}_size'}).first.try(:value)
        "#{blockdevice}: #{disk_size or 'Unknown'}"
      end.join(tag(:br)).html_safe
    end

    def is_pxe?(deployment, subnet)
      subnet_typings(deployment, subnet).any? { |t| t.subnet_type.name == Staypuft::SubnetType::PXE }
    end

    def subnet_types(deployment, subnet)
      subnet_typings(deployment, subnet).map { |t| h(t.subnet_type.name) }.join(' + ')
    end

    def subnet_typings(deployment, subnet)
      deployment.subnet_typings.where(:subnet_id => subnet.id).includes(:subnet_type)
    end
  end

end
