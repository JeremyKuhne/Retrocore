// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  An inferred type: a union-find node, so that locations the code shows must share a type (a VAR parameter and
    ///  its argument, the two sides of an assignment or a comparison) end as one.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A one-word scalar's kind is voted on by how it is used: arithmetic votes for an integer, character I/O and
    ///   string elements for a character, logical operators for a boolean. A location whose kind must be one, such as
    ///   READ's integer, is forced. Where a use disagrees with the kind chosen, the writer converts with
    ///   <c>ORD</c>, <c>CHR</c> or <c>ODD</c>, which compile to nothing.
    ///  </para>
    /// </remarks>
    private sealed class TypeNode
    {
        private static int s_next;
        private TypeNode? _parent;

        /// <summary>
        ///  Initializes a new instance of the <see cref="TypeNode"/> class, of a kind not yet known.
        /// </summary>
        public TypeNode() => Id = ++s_next;

        /// <summary>
        ///  Gets the order it was made in, from 1; where two nodes merge, the older one keeps its identity.
        /// </summary>
        public int Id { get; }

        /// <summary>
        ///  Gets or sets what the type is, as far as the code shows.
        /// </summary>
        public TypeKind Kind { get; set; }

        /// <summary>
        ///  Gets or sets the votes, from how a one-word scalar is used, for its being an integer.
        /// </summary>
        public int IntegerVotes { get; set; }

        /// <summary>
        ///  Gets or sets the votes, from how a one-word scalar is used, for its being a character.
        /// </summary>
        public int CharVotes { get; set; }

        /// <summary>
        ///  Gets or sets the votes, from how a one-word scalar is used, for its being a boolean.
        /// </summary>
        public int BooleanVotes { get; set; }

        /// <summary>
        ///  Gets or sets the kind a one-word scalar must be, whatever the votes, such as READ's integer.
        /// </summary>
        public ScalarKind? Forced { get; set; }

        /// <summary>
        ///  Gets or sets a unit's enumerated type, by name.
        /// </summary>
        public string? Enumeration { get; set; }

        /// <summary>
        ///  Gets or sets the low bound of a subrange a range check gives.
        /// </summary>
        public int? Low { get; set; }

        /// <summary>
        ///  Gets or sets the high bound of a subrange a range check gives.
        /// </summary>
        public int? High { get; set; }

        /// <summary>
        ///  Gets or sets a pointer's target, an array's element, a set's element, or a file's component.
        /// </summary>
        public TypeNode? Element { get; set; }

        /// <summary>
        ///  Gets or sets the low bound of an array's index range.
        /// </summary>
        public int? IndexLow { get; set; }

        /// <summary>
        ///  Gets or sets the high bound of an array's index range.
        /// </summary>
        public int? IndexHigh { get; set; }

        /// <summary>
        ///  Gets or sets an array's element size in words.
        /// </summary>
        public int ElementWords { get; set; }

        /// <summary>
        ///  Gets or sets how many of a packed array's elements a word holds.
        /// </summary>
        public int PerWord { get; set; }

        /// <summary>
        ///  Gets or sets the bits each of a packed array's elements takes.
        /// </summary>
        public int Bits { get; set; }

        /// <summary>
        ///  Gets or sets a value indicating whether a packed array of characters is read and written by byte.
        /// </summary>
        public bool Bytes { get; set; }

        /// <summary>
        ///  Gets or sets a record's fields by word offset.
        /// </summary>
        public SortedDictionary<int, TypeNode>? Fields { get; set; }

        /// <summary>
        ///  Gets or sets a record's packed fields by word and first bit, with their widths.
        /// </summary>
        public SortedDictionary<(int Word, int Bit), (int Width, TypeNode Type)>? PackedFields { get; set; }

        /// <summary>
        ///  Gets or sets its size in words, where the code shows it: a record's, an array's, a set's or a string's.
        /// </summary>
        public int Words { get; set; }

        /// <summary>
        ///  Gets or sets a string's greatest length.
        /// </summary>
        public int MaxLength { get; set; }

        /// <summary>
        ///  Gets or sets a file's record size in words.
        /// </summary>
        public int RecordWords { get; set; }

        /// <summary>
        ///  Gets or sets a value indicating whether it is a word used both as a pointer and as an integer, as through a
        ///  variant record.
        /// </summary>
        public bool Punned { get; set; }

        /// <summary>
        ///  Gets or sets a value indicating whether it is a scalar word also read by bytes, as through a variant record.
        /// </summary>
        public bool ByteView { get; set; }

        /// <summary>
        ///  Gets or sets the name the writer gives it, once declared.
        /// </summary>
        public string? Name { get; set; }

        /// <summary>
        ///  Finds the node that stands for the type, the root of its set, compressing the path to it.
        /// </summary>
        /// <returns>The root.</returns>
        public TypeNode Find()
        {
            TypeNode root = this;
            while (root._parent is not null) { root = root._parent; }

            TypeNode node = this;
            while (node._parent is not null && node._parent != root)
            {
                TypeNode next = node._parent;
                node._parent = root;
                node = next;
            }

            return root;
        }

        /// <summary>
        ///  Makes a node of a kind.
        /// </summary>
        /// <param name="kind">The kind.</param>
        /// <returns>The node.</returns>
        public static TypeNode Of(TypeKind kind) => new() { Kind = kind };

        /// <summary>
        ///  Makes a one-word scalar's node, forced to a kind.
        /// </summary>
        /// <param name="kind">The scalar's kind.</param>
        /// <returns>The node.</returns>
        public static TypeNode Scalar(ScalarKind kind)
        {
            TypeNode node = new() { Kind = TypeKind.Scalar, Forced = kind };
            return node;
        }

        /// <summary>
        ///  Gets the scalar kind the votes choose.
        /// </summary>
        public ScalarKind ScalarKind
        {
            get
            {
                TypeNode root = Find();
                if (root.Enumeration is not null) { return ScalarKind.Enumeration; }
                if (root.Forced is { } forced) { return forced; }
                if (root.BooleanVotes > root.IntegerVotes && root.BooleanVotes >= root.CharVotes)
                {
                    return ScalarKind.Boolean;
                }

                return root.CharVotes > root.IntegerVotes ? ScalarKind.Char : ScalarKind.Integer;
            }
        }

        /// <summary>
        ///  Votes for a one-word scalar's kind, as a use of it shows; a record's vote goes to its first field.
        /// </summary>
        /// <param name="kind">The kind the use shows.</param>
        /// <param name="weight">How many votes the use counts for.</param>
        public void Vote(ScalarKind kind, int weight = 1)
        {
            TypeNode root = Find();

            // A pointer used as an integer is a word used both ways; so is an integer read by bytes.
            if (root.Kind == TypeKind.Pointer && kind == ScalarKind.Integer) { root.Punned = true; }
            if (root.Kind == TypeKind.Array && root.Bytes && kind == ScalarKind.Integer) { root.View(); }
            if (root.Kind == TypeKind.Record)
            {
                root.Field(0).Vote(kind, weight);
                return;
            }

            if (root.Kind == TypeKind.Unknown) { root.Kind = TypeKind.Scalar; }
            switch (kind)
            {
                case ScalarKind.Integer:
                    root.IntegerVotes += weight;
                    break;
                case ScalarKind.Char:
                    root.CharVotes += weight;
                    break;
                case ScalarKind.Boolean:
                    root.BooleanVotes += weight;
                    break;
                default:
                    break;
            }
        }

        /// <summary>
        ///  Forces a one-word scalar's kind, unless one is already forced; a record's goes to its first field.
        /// </summary>
        /// <param name="kind">The kind it must be.</param>
        public void Force(ScalarKind kind)
        {
            TypeNode root = Find();
            if (root.Kind == TypeKind.Pointer && kind == ScalarKind.Integer) { root.Punned = true; }
            if (root.Kind == TypeKind.Record)
            {
                root.Field(0).Force(kind);
                return;
            }

            if (root.Kind == TypeKind.Unknown) { root.Kind = TypeKind.Scalar; }
            root.Forced ??= kind;
        }

        /// <summary>
        ///  Widens a scalar's subrange to take in a range check's bounds; a record's goes to its first field.
        /// </summary>
        /// <param name="low">The range check's low bound.</param>
        /// <param name="high">The range check's high bound.</param>
        public void Range(int low, int high)
        {
            TypeNode root = Find();
            if (root.Kind == TypeKind.Record)
            {
                root.Field(0).Range(low, high);
                return;
            }

            if (root.Kind == TypeKind.Unknown) { root.Kind = TypeKind.Scalar; }
            root.Low = root.Low is { } oldLow ? Math.Min(oldLow, low) : low;
            root.High = root.High is { } oldHigh ? Math.Max(oldHigh, high) : high;
        }

        /// <summary>
        ///  Makes it a pointer, and gives its target.
        /// </summary>
        /// <returns>The pointer's target; for a record, its first field's; for a file, its window, F^.</returns>
        public TypeNode Target()
        {
            TypeNode root = Find();

            // A record's first field is at its address.
            if (root.Kind == TypeKind.Record) { return root.Field(0).Target(); }

            // A file's first word points to its window, F^.
            if (root.Kind is TypeKind.File or TypeKind.Text)
            {
                root.Element ??= new TypeNode();
                return root.Element;
            }

            if (root.Kind is TypeKind.Unknown or TypeKind.Scalar)
            {
                if (root.Kind == TypeKind.Scalar && (root.IntegerVotes > 0 || root.Low is not null))
                {
                    root.Punned = true;
                }

                root.Kind = TypeKind.Pointer;
            }

            if (root.Kind != TypeKind.Pointer) { root.Punned = true; }
            root.Element ??= new TypeNode();
            return root.Element;
        }

        /// <summary>
        ///  Makes it a record, and gives the field at a word offset.
        /// </summary>
        /// <param name="offset">The field's word offset.</param>
        /// <returns>The field's type.</returns>
        public TypeNode Field(int offset)
        {
            TypeNode root = Find();
            if (root.Kind is not (TypeKind.Unknown or TypeKind.Record)) { root.Promote(); }
            if (root.Kind == TypeKind.Unknown) { root.Kind = TypeKind.Record; }
            root.Fields ??= [];
            if (!root.Fields.TryGetValue(offset, out TypeNode? field))
            {
                field = new TypeNode();
                root.Fields[offset] = field;
            }

            return field;
        }

        /// <summary>
        ///  Makes it a record, and gives the packed field at a word and bit.
        /// </summary>
        /// <param name="word">The word offset of the word that holds the field.</param>
        /// <param name="bit">The field's first bit.</param>
        /// <param name="width">The field's width in bits, kept where the field is first seen.</param>
        /// <returns>The field's type.</returns>
        public TypeNode PackedField(int word, int bit, int width)
        {
            TypeNode root = Find();
            if (root.Kind is not (TypeKind.Unknown or TypeKind.Record)) { root.Promote(); }
            if (root.Kind == TypeKind.Unknown) { root.Kind = TypeKind.Record; }
            root.PackedFields ??= [];
            if (!root.PackedFields.TryGetValue((word, bit), out (int Width, TypeNode Type) field))
            {
                field = (width, new TypeNode());
                root.PackedFields[(word, bit)] = field;
            }

            return field.Type;
        }

        /// <summary>
        ///  Makes it an array, and gives its element.
        /// </summary>
        /// <param name="elementWords">The element's size in words.</param>
        /// <param name="low">The index's low bound, if the code shows it.</param>
        /// <param name="high">The index's high bound, if the code shows it.</param>
        /// <returns>The element's type.</returns>
        public TypeNode ArrayElement(int elementWords, int? low, int? high)
        {
            TypeNode root = Find();
            if (root.Kind == TypeKind.Record) { return root.Field(0).ArrayElement(elementWords, low, high); }
            if (root.Kind == TypeKind.Unknown) { root.Kind = TypeKind.Array; }
            root.Element ??= new TypeNode();
            if (root.ElementWords == 0) { root.ElementWords = elementWords; }
            Bounds(root, low, high);
            return root.Element;
        }

        /// <summary>
        ///  Makes it a packed array, and gives its element.
        /// </summary>
        /// <param name="perWord">How many elements a word holds.</param>
        /// <param name="bits">The bits each element takes.</param>
        /// <param name="low">The index's low bound, if the code shows it.</param>
        /// <param name="high">The index's high bound, if the code shows it.</param>
        /// <returns>The element's type.</returns>
        public TypeNode PackedElement(int perWord, int bits, int? low, int? high)
        {
            TypeNode root = Find();
            if (root.Kind == TypeKind.Record) { return root.Field(0).PackedElement(perWord, bits, low, high); }
            if (root.Kind == TypeKind.Unknown) { root.Kind = TypeKind.Array; }
            root.Element ??= new TypeNode();
            if (root.PerWord == 0)
            {
                root.PerWord = perWord;
                root.Bits = bits;
            }

            Bounds(root, low, high);
            return root.Element;
        }

        /// <summary>
        ///  Makes it a packed array read by byte, and gives its element; a scalar read by bytes becomes a variant record's
        ///  two views of a word.
        /// </summary>
        /// <param name="low">The index's low bound, if the code shows it.</param>
        /// <param name="high">The index's high bound, if the code shows it.</param>
        /// <returns>The element's type.</returns>
        public TypeNode ByteElement(int? low, int? high)
        {
            TypeNode root = Find();
            if (root.Kind == TypeKind.Record) { return root.Field(0).ByteElement(low, high); }

            // An integer read by bytes is a variant record's two views of a word.
            if (root.Kind == TypeKind.Scalar)
            {
                root.ByteView = true;
                return root.Element ??= Scalar(ScalarKind.Char);
            }

            if (root.Kind == TypeKind.Unknown) { root.Kind = TypeKind.Array; }
            root.Element ??= new TypeNode();
            if (root.Kind == TypeKind.Array) { root.Bytes = true; }
            Bounds(root, low, high);
            return root.Element;
        }

        /// <summary>
        ///  Makes it a string, and widens its greatest length; a record's goes to its first field.
        /// </summary>
        /// <param name="maxLength">A greatest length the code shows.</param>
        public void String(int maxLength)
        {
            TypeNode root = Find();
            if (root.Kind == TypeKind.Record)
            {
                root.Field(0).String(maxLength);
                return;
            }

            if (root.Kind is TypeKind.Unknown or TypeKind.Array) { root.Kind = TypeKind.String; }
            if (root.Kind == TypeKind.String) { root.MaxLength = Math.Max(root.MaxLength, maxLength); }
        }

        /// <summary>
        ///  Widens its size in words.
        /// </summary>
        /// <param name="words">A size the code shows.</param>
        public void Size(int words)
        {
            TypeNode root = Find();
            root.Words = Math.Max(root.Words, words);
        }

        /// <summary>
        ///  Makes two types one, merging what each shows; where one is a record and the other is not, the other is the
        ///  record's first field.
        /// </summary>
        /// <param name="first">One type.</param>
        /// <param name="second">The other.</param>
        public static void Unify(TypeNode first, TypeNode second)
        {
            TypeNode a = first.Find();
            TypeNode b = second.Find();
            if (a == b) { return; }

            // A record and a thing of another kind at its address: the thing is its first field.
            if (a.Kind == TypeKind.Record && b.Kind is not (TypeKind.Record or TypeKind.Unknown))
            {
                Unify(a.Field(0), b);
                return;
            }

            if (b.Kind == TypeKind.Record && a.Kind is not (TypeKind.Record or TypeKind.Unknown))
            {
                Unify(b.Field(0), a);
                return;
            }

            // The kinds merge into the older node, which keeps its identity.
            if (a.Id > b.Id) { (a, b) = (b, a); }
            b._parent = a;
            if (a.Kind == TypeKind.Unknown)
            {
                a.Kind = b.Kind;
            }
            else if (b.Kind != TypeKind.Unknown && a.Kind != b.Kind)
            {
                // A pointer and a scalar meet in a word used both ways.
                if ((a.Kind, b.Kind) is (TypeKind.Pointer, TypeKind.Scalar) or (TypeKind.Scalar, TypeKind.Pointer))
                {
                    a.Kind = TypeKind.Pointer;
                    a.Punned = true;
                }
                else if (a.Kind == TypeKind.Array && b.Kind == TypeKind.String)
                {
                    a.Kind = TypeKind.String;
                }
                else if ((a.Kind == TypeKind.Array && a.Bytes && b.Kind == TypeKind.Scalar) || (b.Kind == TypeKind.Array && b.Bytes && a.Kind == TypeKind.Scalar))
                {
                    a.Element ??= b.Element;
                    a.View();
                }
            }

            a.IntegerVotes += b.IntegerVotes;
            a.CharVotes += b.CharVotes;
            a.BooleanVotes += b.BooleanVotes;
            a.Forced ??= b.Forced;
            a.Enumeration ??= b.Enumeration;
            a.Punned |= b.Punned;
            a.ByteView |= b.ByteView;
            if (b.Low is { } low) { a.Low = a.Low is { } oldLow ? Math.Min(oldLow, low) : low; }
            if (b.High is { } high) { a.High = a.High is { } oldHigh ? Math.Max(oldHigh, high) : high; }
            Bounds(a, b.IndexLow, b.IndexHigh);
            if (a.ElementWords == 0) { a.ElementWords = b.ElementWords; }
            if (a.PerWord == 0)
            {
                a.PerWord = b.PerWord;
                a.Bits = b.Bits;
            }

            a.Bytes |= b.Bytes;
            a.Words = Math.Max(a.Words, b.Words);
            a.MaxLength = Math.Max(a.MaxLength, b.MaxLength);
            if (a.RecordWords == 0) { a.RecordWords = b.RecordWords; }

            if (b.Element is not null)
            {
                if (a.Element is null)
                {
                    a.Element = b.Element;
                }
                else
                {
                    Unify(a.Element, b.Element);
                }
            }

            if (b.Fields is not null)
            {
                a.Fields ??= [];
                foreach ((int offset, TypeNode field) in b.Fields)
                {
                    if (a.Fields.TryGetValue(offset, out TypeNode? existing))
                    {
                        Unify(existing, field);
                    }
                    else
                    {
                        a.Fields[offset] = field;
                    }
                }
            }

            if (b.PackedFields is not null)
            {
                a.PackedFields ??= [];
                foreach (((int Word, int Bit) key, (int Width, TypeNode Type) field) in b.PackedFields)
                {
                    if (a.PackedFields.TryGetValue(key, out (int Width, TypeNode Type) existing))
                    {
                        Unify(existing.Type, field.Type);
                    }
                    else
                    {
                        a.PackedFields[key] = field;
                    }
                }
            }
        }

        /// <summary>
        ///  Makes a node the code used as one thing into a record of which that thing is the first field, as when a
        ///  record's first field is reached at the record's own address before its others are.
        /// </summary>
        private void Promote()
        {
            TypeNode first = new()
            {
                Kind = Kind,
                IntegerVotes = IntegerVotes,
                CharVotes = CharVotes,
                BooleanVotes = BooleanVotes,
                Forced = Forced,
                Enumeration = Enumeration,
                Low = Low,
                High = High,
                Element = Element,
                IndexLow = IndexLow,
                IndexHigh = IndexHigh,
                ElementWords = ElementWords,
                PerWord = PerWord,
                Bits = Bits,
                Bytes = Bytes,
                Words = Words,
                MaxLength = MaxLength,
                RecordWords = RecordWords,
                Punned = Punned
            };

            Kind = TypeKind.Record;
            IntegerVotes = CharVotes = BooleanVotes = 0;
            Forced = null;
            Enumeration = null;
            Low = High = IndexLow = IndexHigh = null;
            Element = null;
            ElementWords = PerWord = Bits = MaxLength = RecordWords = 0;
            Bytes = Punned = false;
            Words = 0;
            Fields = new SortedDictionary<int, TypeNode> { [0] = first };
        }

        /// <summary>
        ///  Makes a byte array also used as an integer the integer read by bytes.
        /// </summary>
        private void View()
        {
            Kind = TypeKind.Scalar;
            ByteView = true;
            Bytes = false;
            IndexLow = IndexHigh = null;
            Element ??= Scalar(ScalarKind.Char);
        }

        private static void Bounds(TypeNode root, int? low, int? high)
        {
            if (low is { } newLow) { root.IndexLow = root.IndexLow is { } oldLow ? Math.Min(oldLow, newLow) : newLow; }
            if (high is { } newHigh)
            {
                root.IndexHigh = root.IndexHigh is { } oldHigh ? Math.Max(oldHigh, newHigh) : newHigh;
            }
        }
    }
}
