package com.delivery.product.shoppage;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Which chip the bar marks, asked of {@code shop.js} by running it.
 *
 * <p>Every other test of this page reads the bytes the server sent, which is the right way round
 * for markup and is blind to the one thing the bar's behaviour is made of: geometry. A rule that
 * named an aisle the reader had already scrolled past shipped to dev precisely because nothing here
 * could execute it — {@code PublicShopPageFindingTest} could see that the script sets
 * {@code aria-current}, not that it sets it on the right chip.
 *
 * <p>So {@code scrollspy.test.js} beside this class runs the real, unmodified file over a document
 * made of numbers read off a live page with {@code getBoundingClientRect}, and asserts which chip
 * came out marked. It is a replay of measured layout, not a layout engine, and it must stay one: if
 * the page's design changes, those rectangles are re-measured rather than adjusted until green.
 *
 * <p>Node runs it, because there is no JavaScript engine on this classpath and adding one to a
 * Spring service so that a 7 kB file can be tested would be the larger dependency. Where node is
 * absent the test says so and skips, the same bargain
 * {@code PublicShopPageDatabaseTest} makes with PostgreSQL.
 */
@DisplayName("which section the bar says the reader is in")
class ShopPageScrollSpyTest {

    private static final String SCRIPT = "shoppage/shop.js";
    private static final String HARNESS = "shoppage/scrollspy.test.js";

    private static Path unpack(Path into, String resource) throws IOException {
        Path file = into.resolve(resource.substring(resource.lastIndexOf('/') + 1));
        try (InputStream in = ShopPageScrollSpyTest.class.getClassLoader()
                .getResourceAsStream(resource)) {
            assertThat(in).as("%s is on the classpath", resource).isNotNull();
            Files.write(file, in.readAllBytes());
        }
        return file;
    }

    private static boolean nodeIsHere() {
        try {
            Process probe = new ProcessBuilder("node", "--version").redirectErrorStream(true)
                    .start();
            return probe.waitFor(20, TimeUnit.SECONDS) && probe.exitValue() == 0;
        } catch (IOException | InterruptedException absent) {
            Thread.currentThread().interrupt();
            return false;
        }
    }

    @Test
    @DisplayName("the bar always names an aisle the reader can see, on a short menu and a long one")
    void theBarNamesSomethingOnTheScreen(@TempDir Path tmp) throws Exception {
        Assumptions.assumeTrue(nodeIsHere(),
                "node is not on the PATH, so shop.js cannot be run: skipping the scroll-spy cases");

        Path script = unpack(tmp, SCRIPT);
        Path harness = unpack(tmp, HARNESS);

        Process run = new ProcessBuilder("node", harness.toString(), script.toString())
                .redirectErrorStream(true)
                .start();
        String output = new String(run.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        assertThat(run.waitFor(120, TimeUnit.SECONDS)).as("the harness finished").isTrue();

        // The harness prints a line per case; on a failure it is the whole story, so it is attached
        // rather than left in a file nobody opens.
        assertThat(run.exitValue()).as("scroll-spy cases:%n%s", output).isZero();
        assertThat(output).contains("passed");
    }
}
