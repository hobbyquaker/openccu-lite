<#-- openccu-lite: replaces eQ-3's original; the original and this modification are under the Homematic Software License (HMSL) 2.0, see NOTICE.md. -->
<#-- openccu-lite: configureDevices - the members whose configuration is pending - as JSON. -->
<#compress>
{"devices":[<#list devicesList as device>{"id":"${device.getId()?json_string}","serial":"${device.getLabel()?json_string}","type":"${device.getGroupMemberType().getId()?json_string}"}<#sep>,</#list>]}
</#compress>
