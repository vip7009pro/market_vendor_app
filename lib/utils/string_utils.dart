class StringUtils {
  static String normalize(String input) {
    if (input.isEmpty) return "";

    var result = input.toLowerCase();

    // Thay thế các ký tự có dấu thành không dấu
    result = result.replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a');
    result = result.replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e');
    result = result.replaceAll(RegExp(r'[ìíịỉĩ]'), 'i');
    result = result.replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o');
    result = result.replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u');
    result = result.replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y');
    result = result.replaceAll(RegExp(r'[đ]'), 'd');

    // Loại bỏ các ký tự kết hợp (diacritics) nếu có trong chuỗi Unicode đặc biệt
    // (Phòng trường hợp input sử dụng tổ hợp phím gõ Telex khác nhau)
    result = result.replaceAll(RegExp(r'[\u0300\u0301\u0303\u0309\u0323]'), ''); // Huyền, sắc, ngã, hỏi, nặng
    result = result.replaceAll(RegExp(r'[\u02C6\u0306\u031B]'), ''); // Â, Ă, Ơ, Ư

    return result;
  }
}