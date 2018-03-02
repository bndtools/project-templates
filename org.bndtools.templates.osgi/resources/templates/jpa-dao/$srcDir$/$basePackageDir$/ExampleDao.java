package $basePackageName$;

import static java.util.stream.Collectors.toList;

import java.util.List;
import java.util.Map;

import javax.persistence.EntityManager;
import javax.persistence.criteria.CriteriaBuilder;
import javax.persistence.criteria.CriteriaDelete;
import javax.persistence.criteria.CriteriaQuery;
import javax.persistence.criteria.Root;

import org.osgi.service.component.annotations.*;
import org.osgi.service.transaction.control.TransactionControl;
import org.osgi.service.transaction.control.jpa.JPAEntityManagerProvider;
import $basePackageName$.entity.MyEntity;

/**
 * This template provides an example Data Access service using JPA.
 * Typically it should be exposed as an OSGi service by implementing a
 * Data Access Service interface.
 * 
 * <p>
 * This template expects a ready-configured JPAEntityManagerProvider service
 * to be registered. If this is not the case then a
 * JPAEntityManagerProviderFactory can be used in conjunction with the
 * EntityManagerFactoryBuilder to create a JPAEntityManagerProvider
 */

@Component
public class ExampleDao {

    @Reference
    TransactionControl transactionControl;

    /** 
     * This target filter must select the persistence unit defined by
     * the persistence.xml in this bundle
     */
    @Reference(target="(osgi.unit.name=$projectName$-pu)")
    JPAEntityManagerProvider jpaEntityManagerProvider;

    EntityManager em;

    @Activate
    void activate(Map<String, Object> props) {
        em = jpaEntityManagerProvider.getResource(transactionControl);
    }

    private List<MyEntity> select() {

        return transactionControl.notSupported(() -> {

            CriteriaBuilder builder = em.getCriteriaBuilder();
            
            CriteriaQuery<MyEntity> query = builder.createQuery(MyEntity.class);
            
            query.from(MyEntity.class);
            
            return em.createQuery(query).getResultList().stream()
                    .collect(toList());
        });
    }

    private void delete(Long primaryKey) {

        transactionControl.required(() -> {
            CriteriaBuilder builder = em.getCriteriaBuilder();
            
            CriteriaDelete<MyEntity> query = builder.createCriteriaDelete(MyEntity.class);
            
            Root<MyEntity> from = query.from(MyEntity.class);
            
            query.where(builder.equal(from.get("id"), primaryKey));
            
            em.createQuery(query).executeUpdate();
            
            return null;
        });
    }

    private MyEntity findByPK(Long pk) {

       return transactionControl.supports(() -> {
           return em.find(MyEntity.class, pk);
        });
    }
}
