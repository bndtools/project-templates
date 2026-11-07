package template.smoke;

import java.io.FileOutputStream;
import org.osgi.framework.BundleActivator;
import org.osgi.framework.BundleContext;

public class LaunchProbe implements BundleActivator {
    public void start(BundleContext context) throws Exception {
        String marker = System.getenv("TEMPLATE_SMOKE_MARKER");
        if (marker != null) {
            try (FileOutputStream output = new FileOutputStream(marker)) {
                output.write("TEMPLATE_SMOKE_STARTED".getBytes("UTF-8"));
            }
        }
        System.out.println("TEMPLATE_SMOKE_STARTED");
        Thread stopper = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    Thread.sleep(1000L);
                    context.getBundle(0).stop();
                } catch (Exception exception) {
                    exception.printStackTrace();
                }
            }
        }, "template-smoke-stop");
        stopper.setDaemon(true);
        stopper.start();
    }

    public void stop(BundleContext context) {}
}