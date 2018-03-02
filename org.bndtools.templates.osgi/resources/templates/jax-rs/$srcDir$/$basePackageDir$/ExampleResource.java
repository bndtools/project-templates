package $basePackageName$;

import javax.ws.rs.GET;
import javax.ws.rs.Path;

import org.osgi.service.component.annotations.*;
import org.osgi.service.jaxrs.whiteboard.propertytypes.JaxrsResource;

@Component(service=ExampleResource.class)
@JaxrsResource
public class ExampleResource {

	@GET
	@Path("example")
	public String sayHello() {
		return "Hello";
	}

}