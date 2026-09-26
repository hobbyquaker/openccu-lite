<#-- openccu-lite: replaces eQ-3's original; the original and this modification are under the Homematic Software License (HMSL) 2.0, see NOTICE.md. -->
<#-- openccu-lite: listPossibleGroups - the groups a device could join - as JSON. -->
<#compress>
{"groups":[<#list possibleGroupsList as group>{"id":"${group.getId()?c}","name":"${group.getName()?json_string}","type":"${group.getGroupDefinition().getGroupType().getId()?json_string}","typeLabel":"${group.getGroupDefinition().getGroupType().getLabel()?json_string}"}<#sep>,</#list>],
"serialNumber":"${serialNumber?json_string}",
"regaID":"${regaID?json_string}"}
</#compress>
