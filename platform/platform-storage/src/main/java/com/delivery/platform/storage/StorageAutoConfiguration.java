package com.delivery.platform.storage;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;

import io.minio.MinioClient;

/**
 * <strong>The consuming service must scan this package for JPA entities and repositories</strong> —
 * {@code @EntityScan(basePackages = "com.delivery")} and
 * {@code @EnableJpaRepositories(basePackages = "com.delivery")} on its application class.
 *
 * <p>As with {@code platform-outbox}, this class does not declare those annotations itself:
 * {@code @EnableJpaRepositories} on a library switches off Boot's own repository scanning, which
 * silently hides the application's repositories.
 */
@AutoConfiguration(after = HibernateJpaAutoConfiguration.class)
@ConditionalOnClass(MinioClient.class)
@ConditionalOnProperty(prefix = "delivery.storage.minio", name = "access-key")
@EnableConfigurationProperties(StorageProperties.class)
public class StorageAutoConfiguration {

    /** Server-side operations: stat, remove. Reaches MinIO on the internal network. */
    @Bean
    @ConditionalOnMissingBean(name = "internalMinioClient")
    public MinioClient internalMinioClient(StorageProperties properties) {
        return MinioClient.builder()
                .endpoint(properties.getEndpoint())
                .credentials(properties.getAccessKey(), properties.getSecretKey())
                .region(properties.getRegion())
                .build();
    }

    /**
     * Signing only. Built against the public endpoint because a presigned URL's signature covers
     * the host header — one signed for {@code http://minio:9000} fails the moment a browser
     * resolves it as {@code http://localhost:9010}.
     */
    @Bean
    @ConditionalOnMissingBean(name = "presignMinioClient")
    public MinioClient presignMinioClient(StorageProperties properties) {
        return MinioClient.builder()
                .endpoint(properties.getPublicEndpoint())
                .credentials(properties.getAccessKey(), properties.getSecretKey())
                .region(properties.getRegion())
                .build();
    }

    /**
     * Two MinioClients, and which is which matters — one talks to MinIO over the internal network,
     * the other signs URLs against the public endpoint a browser can reach.
     *
     * <p><strong>{@code @Qualifier} rather than relying on the parameter names.</strong> Spring
     * falls back to matching a parameter's NAME against the bean name when a type is ambiguous, and
     * that only works if the class was compiled with {@code -parameters}. This module configures
     * maven-compiler-plugin itself and is not built under the Spring Boot parent, so it was not —
     * every consuming service failed at startup with "required a single bean, but 2 were found".
     *
     * <p>The build now passes {@code -parameters} too, but the annotations stay: they are the half
     * that cannot be silently undone by a compiler setting in a pom somebody edits later.
     */
    @Bean
    @ConditionalOnMissingBean
    public StorageService storageService(@Qualifier("internalMinioClient") MinioClient internalMinioClient,
                                         @Qualifier("presignMinioClient") MinioClient presignMinioClient,
                                         FileMetadataRepository repository,
                                         StorageProperties properties) {
        return new StorageService(internalMinioClient, presignMinioClient, repository, properties);
    }
}
