// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

/// <summary>
///  The offsets of the packed game's header fields, as <c>PackedFormat.md</c> and the 6502 engine's
///  <c>Header</c> struct give them. Each table's field is its offset from the start of the packed game.
/// </summary>
internal static class PackedHeader
{
    /// <summary>
    ///  The two bytes <c>SA</c>.
    /// </summary>
    internal const int Magic = 0;

    /// <summary>
    ///  The format's version, <see cref="CurrentVersion"/>.
    /// </summary>
    internal const int Version = 2;

    /// <summary>
    ///  How many letters of a word are significant.
    /// </summary>
    internal const int WordLength = 3;

    /// <summary>
    ///  The number of items.
    /// </summary>
    internal const int ItemCount = 4;

    /// <summary>
    ///  The number of rooms, room 0 included.
    /// </summary>
    internal const int RoomCount = 5;

    /// <summary>
    ///  The number of messages, message 0 included.
    /// </summary>
    internal const int MessageCount = 6;

    /// <summary>
    ///  The number of verbs, which is also the number of nouns.
    /// </summary>
    internal const int WordCount = 7;

    /// <summary>
    ///  The room the player starts in.
    /// </summary>
    internal const int StartRoom = 8;

    /// <summary>
    ///  The room where treasures are stored.
    /// </summary>
    internal const int TreasureRoom = 9;

    /// <summary>
    ///  The most items the player may carry.
    /// </summary>
    internal const int CarryLimit = 10;

    /// <summary>
    ///  The number of treasures the score counts out of.
    /// </summary>
    internal const int TreasureCount = 11;

    /// <summary>
    ///  The item that gives light.
    /// </summary>
    internal const int LightItem = 12;

    /// <summary>
    ///  The light's turns, a word; <c>$FFFF</c> for a light that never runs out.
    /// </summary>
    internal const int LightTime = 13;

    /// <summary>
    ///  The number of actions, a word.
    /// </summary>
    internal const int ActionCount = 15;

    /// <summary>
    ///  The dictionary.
    /// </summary>
    internal const int Dictionary = 17;

    /// <summary>
    ///  The verbs.
    /// </summary>
    internal const int Verbs = 19;

    /// <summary>
    ///  The nouns.
    /// </summary>
    internal const int Nouns = 21;

    /// <summary>
    ///  The rooms' exits.
    /// </summary>
    internal const int Exits = 23;

    /// <summary>
    ///  The rooms' descriptions.
    /// </summary>
    internal const int RoomTexts = 25;

    /// <summary>
    ///  The messages.
    /// </summary>
    internal const int Messages = 27;

    /// <summary>
    ///  Where each item starts.
    /// </summary>
    internal const int ItemLocations = 29;

    /// <summary>
    ///  The noun GET and DROP know each item by.
    /// </summary>
    internal const int ItemNouns = 31;

    /// <summary>
    ///  A bit for each item that is a treasure.
    /// </summary>
    internal const int Treasures = 33;

    /// <summary>
    ///  The items' descriptions.
    /// </summary>
    internal const int ItemTexts = 35;

    /// <summary>
    ///  The actions.
    /// </summary>
    internal const int Actions = 37;

    /// <summary>
    ///  The header's size.
    /// </summary>
    internal const int Size = 39;

    /// <summary>
    ///  The version this packer writes.
    /// </summary>
    internal const byte CurrentVersion = 1;

    /// <summary>
    ///  The light time of a light that never runs out.
    /// </summary>
    internal const int Endless = 0xFFFF;
}
