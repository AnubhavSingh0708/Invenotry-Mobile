class Reel {
  final int? id; // Primary database key required for modifying existing records
  final String reelId;
  final double sizeCm;
  final double weightKg;
  final int gsm;
  final String bf;
  final String colour;
  final String quality;
  final String? party;
  final String date;
  final String time;
  final String? dispatchDate;
  final String? dispatchTime;
  final String? billedDate;
  final String? billedTime;

  Reel({
    this.id,
    required this.reelId,
    required this.sizeCm,
    required this.weightKg,
    required this.gsm,
    required this.bf,
    required this.colour,
    required this.quality,
    this.party,
    required this.date,
    required this.time,
    this.dispatchDate,
    this.dispatchTime,
    this.billedDate,
    this.billedTime,
  });

  factory Reel.fromJson(Map<String, dynamic> json) {
    return Reel(
      id: json['id'] != null ? (json['id'] as num).toInt() : null,
      reelId: json['reel_id']?.toString() ?? '',
      sizeCm: (json['size_cm'] as num?)?.toDouble() ?? 0.0,
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0.0,
      gsm: json['gsm'] != null ? (json['gsm'] as num).toInt() : 0,
      bf: json['bf']?.toString() ?? '',
      colour: json['colour']?.toString() ?? '',
      quality: json['quality']?.toString() ?? '',
      party: json['party']?.toString(),
      date: json['date']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      dispatchDate: json['dispatch_date']?.toString(),
      dispatchTime: json['dispatch_time']?.toString(),
      billedDate: json['billed_date']?.toString(),
      billedTime: json['billed_time']?.toString(),
    );
  }
}