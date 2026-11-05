package template.smoke;

import org.osgi.framework.BundleActivator;
import org.osgi.framework.BundleContext;

public class LaunchProbe implements BundleActivator {
    public void start(BundleContext context) {
        System.out.println("TEMPLATE_SMOKE_STARTED");
        Thread stopper = new Thread(() -> {
            try {
                Thread.sleep(1000L);
                context.getBundle(0).stop();
            } catch (Exception exception) {
                exception.printStackTrace();
            }
        }, "template-smoke-stop");
        stopper.setDaemon(true);
        stopper.start();
    }

    public void stop(BundleContext context) {}
}