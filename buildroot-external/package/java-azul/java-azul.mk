################################################################################
#
# Azul java runtime - https://www.azul.com/downloads/?package=jre#zulu
#
################################################################################

JAVA_AZUL_VERSION = 21.52.203-ca-jre21.0.12.1
JAVA_AZUL_SITE = https://cdn.azul.com/zulu/bin
ifeq ($(call qstrip,$(BR2_ARCH)),aarch64)
JAVA_AZUL_SOURCE = zulu$(JAVA_AZUL_VERSION)-linux_aarch64.tar.gz
else ifeq ($(call qstrip,$(BR2_ARCH)),x86_64)
JAVA_AZUL_SOURCE = zulu$(JAVA_AZUL_VERSION)-linux_x64.tar.gz
endif
JAVA_AZUL_LICENSE = GPL
JAVA_AZUL_LICENSE_FILES = DISCLAIMER legal/java.base/LICENSE legal/java.base/ADDITIONAL_LICENSE_INFO legal/java.base/ASSEMBLY_EXCEPTION
# The JVM's font stack (AWT only): required when the configuration selects it, so a
# configuration without fontconfig/fonts (no AWT user on the box) can build.
JAVA_AZUL_DEPENDENCIES = \
	$(if $(BR2_PACKAGE_FONTCONFIG),fontconfig) \
	$(if $(BR2_PACKAGE_DEJAVU),dejavu) \
	$(if $(BR2_PACKAGE_LIBERATION),liberation)

define JAVA_AZUL_INSTALL_TARGET_CMDS
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/opt/java-azul
	cp -a $(@D)/bin $(TARGET_DIR)/opt/java-azul/
	cp -a $(@D)/conf $(TARGET_DIR)/opt/java-azul/
	cp -a $(@D)/lib $(TARGET_DIR)/opt/java-azul/
	cp -a $(@D)/legal $(TARGET_DIR)/opt/java-azul/
	cp -a $(@D)/DISCLAIMER $(TARGET_DIR)/opt/java-azul/
	rm -f $(TARGET_DIR)/opt/java
	ln -s java-azul $(TARGET_DIR)/opt/java
endef

$(eval $(generic-package))
