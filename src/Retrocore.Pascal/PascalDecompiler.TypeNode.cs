// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // What a type is, as far as the code shows.
    private enum TypeKind
    {
        Unknown,
        Scalar,
        Real,
        Pointer,
        Record,
        Array,
        String,
        Set,
        File,
        Text
    }

    // What a one-word scalar is: an integer, a character, a boolean, or a unit's enumerated type.
    private enum ScalarKind
    {
        Integer,
        Char,
        Boolean,
        Enumeration
    }

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

        public TypeNode() => Id = ++s_next;

        public int Id { get; }

        public TypeKind Kind { get; set; }

        public int IntegerVotes { get; set; }

        public int CharVotes { get; set; }

        public int BooleanVotes { get; set; }

        public ScalarKind? Forced { get; set; }

        // A unit's enumerated type, by name.
        public string? Enumeration { get; set; }

        // A subrange a range check gives.
        public int? Low { get; set; }

        public int? High { get; set; }

        // A pointer's target, an array's element, a set's element, or a file's component.
        public TypeNode? Element { get; set; }

        // An array's index range.
        public int? IndexLow { get; set; }

        public int? IndexHigh { get; set; }

        // An array's element size in words; a packed array's elements to a word and bits.
        public int ElementWords { get; set; }

        public int PerWord { get; set; }

        public int Bits { get; set; }

        // Whether a packed array of characters is read and written by byte.
        public bool Bytes { get; set; }

        // A record's fields by word offset.
        public SortedDictionary<int, TypeNode>? Fields { get; set; }

        // A record's packed fields by word and first bit, with their widths.
        public SortedDictionary<(int Word, int Bit), (int Width, TypeNode Type)>? PackedFields { get; set; }

        // Its size in words, where the code shows it: a record's, an array's, a set's or a string's.
        public int Words { get; set; }

        // A string's greatest length.
        public int MaxLength { get; set; }

        // A file's record size in words.
        public int RecordWords { get; set; }

        // A word used both as a pointer and as an integer, as through a variant record.
        public bool Punned { get; set; }

        // A scalar word also read by bytes, as through a variant record.
        public bool ByteView { get; set; }

        // The name the writer gives it, once declared.
        public string? Name { get; set; }

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

        public static TypeNode Of(TypeKind kind) => new() { Kind = kind };

        public static TypeNode Scalar(ScalarKind kind)
        {
            TypeNode node = new() { Kind = TypeKind.Scalar, Forced = kind };
            return node;
        }

        // The scalar kind the votes choose.
        public ScalarKind ScalarKind
        {
            get
            {
                TypeNode root = Find();
                if (root.Enumeration is not null) { return ScalarKind.Enumeration; }
                if (root.Forced is { } forced) { return forced; }
                if (root.BooleanVotes > root.IntegerVotes && root.BooleanVotes >= root.CharVotes) { return ScalarKind.Boolean; }
                return root.CharVotes > root.IntegerVotes ? ScalarKind.Char : ScalarKind.Integer;
            }
        }

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

        // Makes it a pointer, and gives its target.
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
                if (root.Kind == TypeKind.Scalar && (root.IntegerVotes > 0 || root.Low is not null)) { root.Punned = true; }
                root.Kind = TypeKind.Pointer;
            }

            if (root.Kind != TypeKind.Pointer) { root.Punned = true; }
            root.Element ??= new TypeNode();
            return root.Element;
        }

        // Makes it a record, and gives the field at a word offset.
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

        // Makes it an array, and gives its element.
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

        public void Size(int words)
        {
            TypeNode root = Find();
            root.Words = Math.Max(root.Words, words);
        }

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

        // Makes a node the code used as one thing into a record of which that thing is the first field, as when a
        // record's first field is reached at the record's own address before its others are.
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

        // Makes a byte array also used as an integer the integer read by bytes.
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
            if (high is { } newHigh) { root.IndexHigh = root.IndexHigh is { } oldHigh ? Math.Max(oldHigh, newHigh) : newHigh; }
        }
    }
}
