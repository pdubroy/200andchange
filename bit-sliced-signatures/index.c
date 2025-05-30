// # Bit-sliced signatures
//
// Bit-sliced signatures are a way to speed up searches by rejecting files that
// don't match a query string.  Each file is split into trigrams, which are
// hashed and inserted into a per-file Bloom filter.  The Bloom filters are then
// transposed, yielding an array of bitmaps indicating which files have each
// given bit set in their respective Bloom filters.  This array is stored as the
// index.
//
// To search using the index, the query string is split into trigrams and hashed
// in the same way.  For a file to contain the query string, it must contain
// all of its trigrams, which means the bits corresponding to the hashes of the
// trigrams in the query must be set.  Intersecting the bitmaps for these bits
// gives the bitmap of files that may contain the query string, allowing the
// full search to look at only those files.
//
// An improved variant of this technique was used (at least for a while) in the
// Bing search engine: <https://www.microsoft.com/en-us/research/publication/bitfunnel-revisiting-signatures-search/>
//
// Built as `cc -O2 -std=c11 -pedantic -Wall -o search-index index.c`.
//
// **License:** This software belongs to a future without copyright.  Please use it however you'd like.<br>
// **Authorship:** [Ian Henderson](http://ianhenderson.org/), May 2025

#define _GNU_SOURCE
#include <fcntl.h>
#include <fts.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
// ---

// From <https://github.com/imneme/pcg-c/blob/master/include/pcg_variants.h>.
// Used as a simple hash function for trigrams.
inline uint32_t pcg_output_rxs_m_xs_32_32(uint32_t state)
{
    uint32_t word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// Information needed to compute the index file size and data offsets.
struct index_metadata {
    uint64_t number_of_files;
    uint64_t length_of_file_paths;
};

// A `struct index_file` is memory-mapped from the index file itself.  The
// `data` field contains, in order:
// 1. the paths to each indexed file, separated by '\0' bytes,
// 2. the offset into the file paths for each file, to avoid having to scan the
//   list to look up a particular file path, and
// 3. the array of bitmaps indicating which files have which bits set in their
//   trigram Bloom filter.
struct index_file {
    struct index_metadata meta;
    uint64_t data[];
};

// A wrapper around a `struct index_file` with easy, precomputed access to the
// different sections of the `data` field, as well as a `stride` field that
// represents the distance between each bitmap in `bitmaps`.
struct index {
    struct index_file *file;
    size_t stride;
    char *file_paths;
    uint64_t *file_path_offsets;
    uint64_t *bitmaps;
};

// The size of the Bloom filter.  The Bloom filter parameters were tuned based
// on the distribution of trigrams in the Linux kernel source.
#define FILTER_BITS 14
#define FILTER_SIZE (1 << FILTER_BITS)
#define FILTER_MASK (FILTER_SIZE - 1)

static uint64_t index_stride(struct index_metadata meta)
{
    // Bits are stored in chunks of 64; round the number of files up to a
    // multiple of 64 so everything is aligned properly.
    return (meta.number_of_files + 63) / 64;
}

// The total size of an index file with the given metadata.
static size_t index_file_size(struct index_metadata meta)
{
    return offsetof(struct index_file, data) + sizeof(uint64_t) * (meta.length_of_file_paths + meta.number_of_files + FILTER_SIZE * index_stride(meta));
}

// Map an index file into memory, initializing its metadata if specified.
static struct index index_mmap(int fd, int prot, struct index_metadata *meta)
{
    struct index index;
    if (meta) {
        ftruncate(fd, index_file_size(*meta));
        index.file = mmap(0, index_file_size(*meta), prot, MAP_SHARED, fd, 0);
        index.file->meta = *meta;
    } else {
        struct index_metadata meta = { 0 };
        pread(fd, &meta, sizeof(meta), 0);
        index.file = mmap(0, index_file_size(meta), prot, MAP_SHARED, fd, 0);
    }
    index.stride = index_stride(index.file->meta);
    index.file_paths = (char *)index.file->data;
    index.file_path_offsets = index.file->data + index.file->meta.length_of_file_paths;
    index.bitmaps = index.file->data + index.file->meta.length_of_file_paths + index.file->meta.number_of_files;
    return index;
}

static void index_munmap(struct index index)
{
    munmap(index.file, index_file_size(index.file->meta));
}

// Given a file path that's already been written to the `file_paths` part of the
// index file, `index_add_file` records its offset in `file_path_offsets`, then
// iterates over each trigram in the file, adding bits to the proper bitmaps as
// it goes.
static void index_add_file(struct index index, size_t file_path_offset, uint64_t which_file)
{
    index.file_path_offsets[which_file] = file_path_offset;
    int fd = open(index.file_paths + file_path_offset, O_RDONLY);
    struct stat file_stat;
    fstat(fd, &file_stat);
    if (file_stat.st_size >= 3) {
        uint8_t *data = mmap(0, file_stat.st_size, PROT_READ, MAP_SHARED, fd, 0);
        uint32_t trigram = ((uint32_t)data[0] << 8) | (uint32_t)data[1];
        for (off_t i = 2; i < file_stat.st_size; ++i) {
            trigram = ((trigram << 8) & 0xfffffful) | data[i];
            uint32_t hash = pcg_output_rxs_m_xs_32_32(trigram);
            // Note that each trigram sets two bits; this is one of the tunable
            // parameters of the Bloom filter.
            index.bitmaps[index.stride * (hash & FILTER_MASK) + which_file / 64] |= 1ull << (which_file % 64);
            index.bitmaps[index.stride * ((hash >> FILTER_BITS) & FILTER_MASK) + which_file / 64] |= 1ull << (which_file % 64);
        }
        munmap(data, file_stat.st_size);
    }
    close(fd);
}

// Perform a search over the files using the index.
static void index_search(struct index index, char *query)
{
    // First, intersect the bitmaps for each trigram in `query_bitmap`.
    uint64_t *query_bitmap = malloc(index.stride * sizeof(uint64_t));
    memset(query_bitmap, 0xff, index.stride * sizeof(uint64_t));
    size_t query_length = strlen(query);
    if (query_length >= 3) {
        uint32_t trigram = ((uint32_t)query[0] << 8) | (uint32_t)query[1];
        for (size_t i = 2; i < query_length; ++i) {
            trigram = ((trigram << 8) & 0xfffffful) | query[i];
            uint32_t hash = pcg_output_rxs_m_xs_32_32(trigram);
            for (size_t j = 0; j < index.stride; ++j) {
                query_bitmap[j] &= index.bitmaps[index.stride * (hash & FILTER_MASK) + j];
                query_bitmap[j] &= index.bitmaps[index.stride * ((hash >> FILTER_BITS) & FILTER_MASK) + j];
            }
        }
    }
    // Then iterate over the bits of `query_bitmap`, searching each file which
    // has its bit set.  False positives are possible, but don't require any
    // extra logic to deal with, since no matches will be found and no lines
    // will be printed.
    for (uint64_t i = 0; i < index.stride; ++i) {
        // If all the bits are zero, skip the whole group of 64 files.
        if (!query_bitmap[i])
            continue;
        for (int j = 0; j < 64; ++j) {
            if (i * 64 + j >= index.file->meta.number_of_files)
                break;
            if (!(query_bitmap[i] & (1ull << j)))
                continue;
            char *file_path = index.file_paths + index.file_path_offsets[i * 64 + j];
            int fd = open(file_path, O_RDONLY);
            struct stat file_stat;
            fstat(fd, &file_stat);
            uint8_t *data_start = mmap(0, file_stat.st_size, PROT_READ, MAP_SHARED, fd, 0);
            close(fd);
            uint8_t *data_end = data_start + file_stat.st_size;
            uint8_t *line_end = data_start;
            uint8_t *match;
            while ((match = memmem(line_end, data_end - line_end, query, query_length))) {
                // Find the beginning and end of the line containing the match.
                line_end = memchr(match + query_length, '\n', data_end - (match + query_length));
                if (!line_end)
                    line_end = data_end;
                uint8_t *line_start = match;
                while (line_start > data_start && line_start[-1] != '\n')
                    line_start--;
                printf("%s: ", file_path);
                fwrite(line_start, 1, line_end - line_start, stdout);
                fputc('\n', stdout);
            }
            munmap(data_start, file_stat.st_size);
        }
    }
    free(query_bitmap);
}

static void usage(void)
{
    fprintf(stderr, "USAGE\n");
    fprintf(stderr, "  search-index index [index file path] <directory path>\n");
    fprintf(stderr, "    creates an index for the given directory at the given index file path.\n");
    fprintf(stderr, "    the index file path defaults to 'search.index' if unspecified.\n");
    fprintf(stderr, "  search-index search [index file path] <query string>\n");
    fprintf(stderr, "    performs a search for the given query string using the index file.\n");
    fprintf(stderr, "    the index file path defaults to 'search.index' if unspecified.\n");
    exit(1);
}

int main(int argc, char *argv[])
{
    if (argc < 3)
        usage();
    char *index_file_path = "search.index";
    char *query = argv[2];
    if (argc == 4) {
        index_file_path = argv[2];
        query = argv[3];
    } else if (argc > 4)
        usage();
    if (strcmp(argv[1], "index") == 0) {
        // To build the index, start by using normal C I/O functions to write
        // the list of file paths.  After that's done, the final length of the
        // index file is known, and mmap is used to write the rest of the data.
        FILE *index_file = fopen(index_file_path, "w+");
        if (!index_file) {
            fprintf(stderr, "couldn't open index file at '%s'.\n", index_file_path);
            exit(1);
        }
        struct index_metadata meta = { 0 };
        // Leave space for the metadata at the beginning of the file.
        fwrite(&meta, sizeof(meta), 1, index_file);
        // Iterate over the directory, writing each path to the file.
        FTS *fts = fts_open((char *[]){ query, NULL }, FTS_PHYSICAL, NULL);
        if (!fts) {
            fprintf(stderr, "couldn't read directory at '%s'.\n", query);
            exit(1);
        }
        FTSENT *entry;
        while ((entry = fts_read(fts)) != NULL) {
            if (entry->fts_info != FTS_F)
                continue;
            // Include the NULL terminator when writing a path -- it's used as a
            // separator.
            fwrite(entry->fts_path, 1, entry->fts_pathlen + 1, index_file);
            meta.number_of_files++;
            meta.length_of_file_paths += entry->fts_pathlen + 1;
        }
        // Rescale `length_of_file_paths` so it can be used as an index into the
        // `data` array of 64-bit integers.
        meta.length_of_file_paths = (meta.length_of_file_paths + sizeof(uint64_t) - 1) / sizeof(uint64_t);
        fts_close(fts);
        fflush(index_file);
        struct index index = index_mmap(fileno(index_file), PROT_READ | PROT_WRITE, &meta);
        fclose(index_file);
        size_t file_path_offset = 0;
        fprintf(stderr, "building index.");
        for (size_t which_file = 0; which_file < meta.number_of_files; which_file++) {
            if (!(which_file % 5000))
                fprintf(stderr, ".");
            index_add_file(index, file_path_offset, which_file);
            file_path_offset += strlen(index.file_paths + file_path_offset) + 1;
        }
        fprintf(stderr, " done.\n");
        index_munmap(index);
    } else if (strcmp(argv[1], "search") == 0) {
        int index_fd = open(index_file_path, O_RDONLY);
        if (index_fd < 0) {
            fprintf(stderr, "couldn't open index file at '%s'.\n", index_file_path);
            exit(1);
        }
        struct index index = index_mmap(index_fd, PROT_READ, NULL);
        close(index_fd);
        index_search(index, query);
        index_munmap(index);
    } else
        usage();
}
