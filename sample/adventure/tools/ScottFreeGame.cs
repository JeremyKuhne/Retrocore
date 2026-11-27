// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

/// <summary>
///  A game read from the ScottFree <c>.dat</c> text format: a header of counts, then the actions, the words, the
///  rooms, the messages, the items and the actions' comments, as whitespace-separated numbers and quoted strings.
/// </summary>
internal sealed class ScottFreeGame
{
    /// <summary>
    ///  The location the format gives an item that the player carries.
    /// </summary>
    internal const int Carried = 255;

    /// <summary>
    ///  The item that gives light.
    /// </summary>
    internal const int LightItem = 9;

    /// <summary>
    ///  The most items a player may carry.
    /// </summary>
    internal int CarryLimit { get; private init; }

    /// <summary>
    ///  The room the player starts in.
    /// </summary>
    internal int StartRoom { get; private init; }

    /// <summary>
    ///  How many treasures the game has, as its header gives it.
    /// </summary>
    internal int TreasureCount { get; private init; }

    /// <summary>
    ///  How many letters of a word are significant.
    /// </summary>
    internal int WordLength { get; private init; }

    /// <summary>
    ///  How many turns the light lasts, or -1 for a light that never runs out.
    /// </summary>
    internal int LightTime { get; private init; }

    /// <summary>
    ///  The room where treasures are stored for the score.
    /// </summary>
    internal int TreasureRoom { get; private init; }

    /// <summary>
    ///  The actions, in the order the game gives them.
    /// </summary>
    internal List<GameAction> Actions { get; } = [];

    /// <summary>
    ///  The verbs, a <c>*</c> marking a synonym of the word before it.
    /// </summary>
    internal List<string> Verbs { get; } = [];

    /// <summary>
    ///  The nouns, a <c>*</c> marking a synonym of the word before it.
    /// </summary>
    internal List<string> Nouns { get; } = [];

    /// <summary>
    ///  The rooms.
    /// </summary>
    internal List<GameRoom> Rooms { get; } = [];

    /// <summary>
    ///  The messages the actions print.
    /// </summary>
    internal List<string> Messages { get; } = [];

    /// <summary>
    ///  The items.
    /// </summary>
    internal List<GameItem> Items { get; } = [];

    /// <summary>
    ///  Reads a game.
    /// </summary>
    /// <param name="text">The <c>.dat</c> file's text.</param>
    /// <returns>The game.</returns>
    /// <exception cref="InvalidDataException">The text is not a game in the format.</exception>
    internal static ScottFreeGame Parse(string text)
    {
        DatReader reader = new(text);
        reader.Number();
        int items = reader.Number() + 1;
        int actions = reader.Number() + 1;
        int words = reader.Number() + 1;
        int rooms = reader.Number() + 1;
        int carryLimit = reader.Number();
        int startRoom = reader.Number();
        int treasureCount = reader.Number();
        int wordLength = reader.Number();
        int lightTime = reader.Number();
        int messages = reader.Number() + 1;
        ScottFreeGame game = new()
        {
            CarryLimit = carryLimit,
            StartRoom = startRoom,
            TreasureCount = treasureCount,
            WordLength = wordLength,
            LightTime = lightTime,
            TreasureRoom = reader.Number()
        };

        for (int index = 0; index < actions; index++)
        {
            int vocabulary = reader.Number();
            List<GameCondition> conditions = [];
            for (int condition = 0; condition < 5; condition++)
            {
                int value = reader.Number();
                conditions.Add(new(value % 20, value / 20));
            }

            List<int> codes = [];
            for (int pair = 0; pair < 2; pair++)
            {
                int value = reader.Number();
                codes.Add(value / 150);
                codes.Add(value % 150);
            }

            game.Actions.Add(new(vocabulary / 150, vocabulary % 150, conditions, codes));
        }

        for (int index = 0; index < words; index++)
        {
            game.Verbs.Add(reader.Text());
            game.Nouns.Add(reader.Text());
        }

        for (int index = 0; index < rooms; index++)
        {
            int[] exits = new int[6];
            for (int exit = 0; exit < exits.Length; exit++)
            {
                exits[exit] = reader.Number();
            }

            game.Rooms.Add(new(exits, reader.Text()));
        }

        for (int index = 0; index < messages; index++)
        {
            game.Messages.Add(reader.Text());
        }

        for (int index = 0; index < items; index++)
        {
            string description = reader.Text();
            int location = reader.Number();
            game.Items.Add(new(description, location < 0 ? Carried : location));
        }

        return game;
    }
}
