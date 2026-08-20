package com.delivery.platform.storage;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface FileMetadataRepository extends JpaRepository<FileMetadata, UUID> {

    Optional<FileMetadata> findByBucketAndObjectKey(String bucket, String objectKey);

    List<FileMetadata> findByOwnerIdAndPurposeAndStatus(
            String ownerId, FilePurpose purpose, FileMetadata.Status status);

    List<FileMetadata> findByObjectKeyIn(List<String> objectKeys);
}
