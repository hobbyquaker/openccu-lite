<#-- openccu-lite: replaces eQ-3's original; the original and this modification are under the Homematic Software License (HMSL) 2.0, see NOTICE.md. -->
<#-- openccu-lite: the group editor's model as JSON - the group, its members, what it
     could take, what fits no group any more, the types. The names are the WebUI's GroupEditPage.ftl's. -->
<#compress>
{"id":${object.id?c},
"isNew":${isNewGroup?c},
"executeDeviceRefresh":${executeDeviceRefresh?c},
"regaId":"${(addedRegaId!"")?json_string}",
"name":"${(object.name!"")?json_string}",
"groupDeviceName":<#if object.groupDeviceName??>"${object.groupDeviceName?json_string}"<#else>""</#if>,
"forbidSingleOperation":${isSingleOperationForbidden},
"types":[<#list possibleGroupTypes as deviceType>{"id":"${deviceType.getId()?json_string}","label":"${deviceType.getLabel()?json_string}"}<#sep>,</#list>],
"type":"${groupType.getId()?json_string}",
"assignable":[<#list assignableDevices as m>{"id":"${m.getId()?json_string}","serial":"${m.getLabel()?json_string}","type":"${m.getGroupMemberType().getId()?json_string}"}<#sep>,</#list>],
"assigned":[<#list object.getGroupMembers() as m>{"id":"${m.getId()?json_string}","serial":"${m.getLabel()?json_string}","type":"${m.getGroupMemberType().getId()?json_string}"}<#sep>,</#list>],
"leftover":[<#list leftoverDevices as m>{"id":"${m.getId()?json_string}","serial":"${m.getLabel()?json_string}","type":"${m.getGroupMemberType().getId()?json_string}"}<#sep>,</#list>]}
</#compress>
