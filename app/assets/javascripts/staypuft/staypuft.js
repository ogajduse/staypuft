// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// the compiled file.
//
// WARNING: THE FIRST BLANK LINE MARKS THE END OF WHAT'S TO BE PROCESSED, ANY BLANK LINE SHOULD
// GO AFTER THE REQUIRES BELOW.
//
//= require_tree .

$(function () {
  // Check all checkboxes in table
  $('#check_all').on('change', function (e) {
    var table = $(e.target).closest('table');
    $('td input:checkbox', table).attr('checked', e.target.checked);
    $('td input:checkbox', table).closest("tr").toggleClass("info", this.checked);
  });

  $("tr.checkbox_highlight input:checkbox").on('change', function (e) {
    var tr = $(this).closest("tr");
    tr.toggleClass("info", this.checked);
    if (tr.hasClass("deployed")) {
      tr.toggleClass("danger", !this.checked);
    }
  });

  showPasswords();
  $("input[name='staypuft_deployment[passwords][mode]']").change(showPasswords);
  function showPasswords() {
    if ($('#staypuft_deployment_passwords_mode_single').is(":checked")) {
      $('.single_password').show();
    }
    else {
      $('.single_password').hide();
    }
  }

  showNovaVlanRange();
  $("input[name='staypuft_deployment[nova][network_manager]']").change(showNovaVlanRange);
  function showNovaVlanRange() {
    if ($('#staypuft_deployment_nova_network_manager_vlanmanager').is(":checked")) {
      $('.nova_vlan_range').show();
    }
    else {
      $('.nova_vlan_range').hide();
    }
  }

  showNeutronVlanRange();
  $("input[name='staypuft_deployment[neutron][network_segmentation]']").change(showNeutronVlanRange);
  function showNeutronVlanRange() {
    if ($('#staypuft_deployment_neutron_network_segmentation_vlan').is(":checked")) {
      $('.neutron_tenant_vlan_ranges').show();
    }
    else {
      $('.neutron_tenant_vlan_ranges').hide();
    }
  }

  showNeutronExternalInterface();
  $("input[name='staypuft_deployment[neutron][use_external_interface]']").change(showNeutronExternalInterface);
  function showNeutronExternalInterface() {
    if ($('#staypuft_deployment_neutron_use_external_interface').is(":checked")) {
      $('.neutron_external_interface').show();
    }
    else {
      $('.neutron_external_interface').hide();
    }
  }

  showNeutronExternalVlan();
  $("input[name='staypuft_deployment[neutron][use_vlan_for_external_network]']").change(showNeutronExternalVlan);
  function showNeutronExternalVlan() {
    if ($('#staypuft_deployment_neutron_use_vlan_for_external_network').is(":checked")) {
      $('.neutron_external_vlan').show();
    }
    else {
      $('.neutron_external_vlan').hide();
    }
  }

  if($('.configuration').length > 0){
    $('.configuration').find('li').first().find('a')[0].click();
  }

});
