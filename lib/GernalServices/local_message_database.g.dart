// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_message_database.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalMessageAdapter extends TypeAdapter<LocalMessage> {
  @override
  final int typeId = 10;

  @override
  LocalMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalMessage(
      id: fields[0] as String,
      chatId: fields[1] as String,
      senderId: fields[2] as String,
      recipientId: fields[3] as String,
      content: fields[4] as String,
      createdAt: fields[5] as DateTime,
      editedAt: fields[6] as DateTime?,
      status: fields[7] as String,
      isEdited: fields[8] as bool,
      isDeleted: fields[9] as bool,
      attachmentUrls: (fields[10] as List?)?.cast<String>(),
      isSynced: fields[11] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, LocalMessage obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.chatId)
      ..writeByte(2)
      ..write(obj.senderId)
      ..writeByte(3)
      ..write(obj.recipientId)
      ..writeByte(4)
      ..write(obj.content)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.editedAt)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.isEdited)
      ..writeByte(9)
      ..write(obj.isDeleted)
      ..writeByte(10)
      ..write(obj.attachmentUrls)
      ..writeByte(11)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class LocalChatThreadAdapter extends TypeAdapter<LocalChatThread> {
  @override
  final int typeId = 11;

  @override
  LocalChatThread read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalChatThread(
      id: fields[0] as String,
      participantIds: (fields[1] as List).cast<String>(),
      participants: (fields[2] as Map).cast<String, dynamic>(),
      lastMessageContent: fields[3] as String,
      updatedAt: fields[4] as DateTime,
      lastSenderId: fields[5] as String?,
      lastMessageId: fields[6] as String?,
      unreadCounts: (fields[7] as Map).cast<String, int>(),
    );
  }

  @override
  void write(BinaryWriter writer, LocalChatThread obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.participantIds)
      ..writeByte(2)
      ..write(obj.participants)
      ..writeByte(3)
      ..write(obj.lastMessageContent)
      ..writeByte(4)
      ..write(obj.updatedAt)
      ..writeByte(5)
      ..write(obj.lastSenderId)
      ..writeByte(6)
      ..write(obj.lastMessageId)
      ..writeByte(7)
      ..write(obj.unreadCounts);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalChatThreadAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
