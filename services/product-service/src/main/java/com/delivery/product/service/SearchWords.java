package com.delivery.product.service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * One search term as the item search and the shelf search hand it to SQL: the term folded, and the
 * words of it that are matched.
 *
 * <p>Built from what {@code search_fold} (V37) returned for the term
 * ({@code ProductRepository#foldForSearch}), never from a Java copy of the fold, so the words counted
 * and checked here are exactly the words the database compares. A folded term is words of a-z, 0-9
 * and Arabic letters with single spaces between them.
 *
 * <p>A word of one character is not matched on its own: "l" of "1.5 l" or "a" of "a." is in most names
 * in the catalogue, and no index can narrow by it. It still counts as part of the phrase. The words
 * that are matched go longest first, because the queries narrow by the first one (the index reads
 * least for the longest word) and let only the first one match by sound.
 *
 * @param phrase the folded term, or {@code ''}
 * @param words  its words of {@value #MIN_WORD_LENGTH} characters or more, longest first; ties keep
 *               the order they were typed in
 */
public record SearchWords(String phrase, List<String> words) {

    /** The shortest word matched on its own. See the class comment. */
    public static final int MIN_WORD_LENGTH = 2;

    /** An unused slot: nothing to match, and {@code ''} to every query, which never binds null. */
    public static final SearchWords NONE = new SearchWords("", List.of());

    public SearchWords {
        words = List.copyOf(words);
    }

    public static SearchWords of(String folded) {
        String phrase = folded == null ? "" : folded.strip();
        if (phrase.isEmpty()) {
            return NONE;
        }
        List<String> words = new ArrayList<>();
        for (String word : phrase.split(" ")) {
            if (length(word) >= MIN_WORD_LENGTH) {
                words.add(word);
            }
        }
        // A stable sort, so of two equally long words the first typed leads.
        words.sort(Comparator.comparingInt(SearchWords::length).reversed());
        return new SearchWords(phrase, words);
    }

    /** Whether no word is long enough to match: a term like "a." or "1 l", which cannot be searched. */
    public boolean isEmpty() {
        return words.isEmpty();
    }

    /** The words as the queries take them: space-separated, longest first; {@code ''} when none. */
    public String wordsForQuery() {
        return String.join(" ", words);
    }

    /** Characters as SQL's {@code char_length} counts them. */
    private static int length(String word) {
        return word.codePointCount(0, word.length());
    }
}
