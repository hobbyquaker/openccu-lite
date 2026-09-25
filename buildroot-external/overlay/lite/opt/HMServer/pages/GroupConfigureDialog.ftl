<#-- openccu-lite: configureDevices - the members whose configuration is pending - as JSON. -->
<#compress>
{"devices":[<#list devicesList as device>{"id":"${device.getId()?json_string}","serial":"${device.getLabel()?json_string}","type":"${device.getGroupMemberType().getId()?json_string}"}<#sep>,</#list>]}
</#compress>
