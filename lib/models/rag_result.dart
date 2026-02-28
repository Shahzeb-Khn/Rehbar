/// Data model for a RAG query result from the backend
class RagResult {
  final String transcript;
  final String answer;
  final List<String> sources;
  final int chunksFound;

  const RagResult({
    required this.transcript,
    required this.answer,
    required this.sources,
    required this.chunksFound,
  });

  factory RagResult.fromJson(Map<String, dynamic> json) {
    return RagResult(
      transcript: json['transcript'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      sources: List<String>.from(json['sources'] as List? ?? []),
      chunksFound: json['chunks_found'] as int? ?? 0,
    );
  }
}
