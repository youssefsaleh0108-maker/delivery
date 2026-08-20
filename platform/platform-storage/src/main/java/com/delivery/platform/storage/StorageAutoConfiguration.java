package com.delivery.platform.storage;

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

    @Bean
    @ConditionalOnMissingBean
    public StorageService storageService(MinioClient internalMinioClient,
                                         MinioClient presignMinioClient,
                                         FileMetadataRepository repository,
                                         StorageProperties properties) {
        return new StorageService(internalMinioClient, presignMinioClient, repository, properties);
    }
}
