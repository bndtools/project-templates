package $basePackageName$.entity;

import static javax.persistence.GenerationType.IDENTITY;

import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.Id;

/**
 * <p>
 * This is a JPA entity type that will used to persist data to a database. 
 * It should be used in conjunction with the OSGi JPA service. The metadata 
 * necessary to require and interact with the OSGi JPA service is declared 
 * by the package-info.java file in this package.
 * </p>
 * 
 */
@Entity
public class MyEntity {

	@GeneratedValue(strategy = IDENTITY)
    @Id
    private Long id;
	
	// TODO: provide the definition of this Entity

}
