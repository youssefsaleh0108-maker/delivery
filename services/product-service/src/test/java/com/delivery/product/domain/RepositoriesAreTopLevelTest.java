package com.delivery.product.domain;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.AnnotatedBeanDefinition;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AssignableTypeFilter;
import org.springframework.data.repository.Repository;

/**
 * Every Spring Data repository in the domain must be a top-level interface.
 *
 * <p>Spring Data's repository scan only detects package-level interfaces. A set of repositories
 * declared as nested members of a holder class compiled, passed every unit test in this module —
 * none of which loads a Spring context — and then failed the first real deploy of the staff feature
 * with "No qualifying bean of type StaffRepositories$Members". This test is the cheapest guard that
 * would have caught that before it left the laptop: no context, no database, just the classpath.
 */
class RepositoriesAreTopLevelTest {

    /**
     * A scanner that admits interfaces.
     *
     * <p>The stock provider only proposes concrete classes, which would make a scan for repository
     * interfaces return nothing and let the first assertion below pass for the wrong reason.
     */
    private static ClassPathScanningCandidateComponentProvider repositoryScanner() {
        ClassPathScanningCandidateComponentProvider scanner =
                new ClassPathScanningCandidateComponentProvider(false) {
                    @Override
                    protected boolean isCandidateComponent(AnnotatedBeanDefinition definition) {
                        return definition.getMetadata().isInterface();
                    }
                };
        scanner.addIncludeFilter(new AssignableTypeFilter(Repository.class));
        return scanner;
    }

    private static List<String> repositoriesUnder(String basePackage) {
        return repositoryScanner().findCandidateComponents(basePackage).stream()
                .map(BeanDefinition::getBeanClassName)
                // Only the interfaces this module declares — not Spring Data's own base types.
                .filter(name -> name != null && name.startsWith("com.delivery.product"))
                .toList();
    }

    @Test
    @DisplayName("no repository interface is nested inside another type")
    void everyRepositoryIsTopLevel() {
        List<String> nested = repositoriesUnder("com.delivery.product").stream()
                .filter(name -> name.contains("$"))
                .toList();

        assertThat(nested)
                .as("repositories declared as nested types are invisible to Spring Data's scan")
                .isEmpty();
    }

    @Test
    @DisplayName("the scan actually sees the staff repositories")
    void staffRepositoriesAreFound() {
        // Guards the guard: if the scanner were silently finding nothing, the test above would be
        // green for the wrong reason. These four are the ones that shipped nested the first time.
        assertThat(repositoriesUnder("com.delivery.product.domain.staff")).contains(
                "com.delivery.product.domain.staff.StaffMemberRepository",
                "com.delivery.product.domain.staff.StoreRolePermissionRepository",
                "com.delivery.product.domain.staff.StaffInviteRepository",
                "com.delivery.product.domain.staff.StaffShiftRepository");
    }
}
