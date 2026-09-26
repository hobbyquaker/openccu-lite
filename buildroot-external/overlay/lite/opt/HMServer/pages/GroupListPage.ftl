<#-- openccu-lite: replaces eQ-3's original; the original and this modification are under the Homematic Software License (HMSL) 2.0, see NOTICE.md. -->
<#-- openccu-lite: hmipserver's group list as JSON instead of the WebUI's knockout page.
     occulited is the only client of the group pages here (internal/hmgroups); the model is the
     one the WebUI's GroupListPage.ftl reads. FreeMarker 2.3.34 (HMIPServer.jar): ?json_string. -->
<#compress>
{"groups":[<#list objectList as group>{"id":"${group.getId()?c}","name":"${group.getName()?json_string}","type":"${group.getGroupDefinition().getGroupType().getId()?json_string}","typeLabel":"${group.getGroupDefinition().getGroupType().getLabel()?json_string}"}<#sep>,</#list>],
"devicesToConfigure":[<#list devicesToConfigure as d>{"id":"${(d.id!"")?json_string}","serial":"${(d.serialNumber!"")?json_string}","type":"${(d.type!"")?json_string}"}<#sep>,</#list>]}
</#compress>
