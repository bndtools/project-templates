/**
 * <p>
 * This package requires the OSGi JPA service to process the persistence.xml
 * file inside this bundle. It therefore sets the Meta-Persistence header,
 * and requires the JPA Service extender.<p>
 */

@org.osgi.service.jpa.annotations.RequireJPAExtender
@org.osgi.annotation.bundle.Header(name="Meta-Persistence", value="META-INF/persistence.xml")
package $basePackageName$.entity;
