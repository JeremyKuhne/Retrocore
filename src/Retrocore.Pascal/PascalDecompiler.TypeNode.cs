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
        ///  Gets or sets how many elements the code shows an array has, as WRITE shows of the bytes it writes, where it
        ///  shows no bounds: the array is as long, from wherever it starts.
        /// </summary>
        public int? Count { get; set; }

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
        ///  Gets or sets a record's other fields by word offset: the variants' fields at offsets where the code uses
        ///  one word as a pointer and another as an integer, as in a record with a variant part.
        /// </summary>
        public SortedDictionary<int, List<TypeNode>>? Variants { get; set; }

        /// <summary>
        ///  Gets a record's fields and its variants' fields.
        /// </summary>
        public IEnumerable<TypeNode> AllFields =>
            (Fields?.Values ?? Enumerable.Empty<TypeNode>()).Concat(Variants?.Values.SelectMany(list => list) ?? []);

        /// <summary>
        ///  Gets the distinct types of a record's fields at a word offset: its field's first, then its variants'.
        /// </summary>
        /// <param name="offset">The word offset.</param>
        /// <returns>The types, none where the record has no field there.</returns>
        public List<TypeNode> Alternatives(int offset)
        {
            TypeNode root = Find();
            List<TypeNode> alternatives = [];
            if (root.Fields?.TryGetValue(offset, out TypeNode? field) == true) { alternatives.Add(field.Find()); }
            foreach (TypeNode variant in root.Variants?.GetValueOrDefault(offset) ?? [])
            {
                if (!alternatives.Contains(variant.Find())) { alternatives.Add(variant.Find()); }
            }

            return alternatives;
        }

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
        ///  Gets or sets the words of a file's variable before its window, as its FINIT shows them: Apple Pascal's are
        ///  300, Apple III Pascal's 550; 0 where no FINIT shows them.
        /// </summary>
        public int WindowWords { get; set; }

        /// <summary>
        ///  Gets or sets a value indicating whether it is a word used both as a pointer and as an integer, as through a
        ///  variant record.
        /// </summary>
        public bool Punned { get; set; }

        /// <summary>
        ///  Gets or sets a value indicating whether code moves it whole, as the Compiler moves only records and arrays.
        /// </summary>
        public bool Moved { get; set; }

        /// <summary>
        ///  Gets or sets the other types a word used both ways points to, besides <see cref="Element"/>, where the code
        ///  reads what it points to as types that cannot be one: each is another variant's pointer.
        /// </summary>
        public List<TypeNode>? Views { get; set; }

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

            // A pointer used as an integer is ORD of it, which compiles to nothing; an integer read by bytes is a word
            // used both ways.
            if (root.Kind == TypeKind.Pointer && kind == ScalarKind.Integer) { return; }
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

            // A byte is a scalar: a character, or a small number.
            if (root.Kind == TypeKind.Unknown) { root.Kind = TypeKind.Array; }
            root.Element ??= Of(TypeKind.Scalar);
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
                a.Field(0);
                Merge(a, 0, b);
                return;
            }

            if (b.Kind == TypeKind.Record && a.Kind is not (TypeKind.Record or TypeKind.Unknown))
            {
                b.Field(0);
                Merge(b, 0, a);
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
            a.Moved |= b.Moved;
            if (b.Views is { } views)
            {
                a.Views ??= [];
                a.Views.AddRange(views.Where(view => !a.Views.Contains(view)));
            }

            a.ByteView |= b.ByteView;
            if (b.Low is { } low) { a.Low = a.Low is { } oldLow ? Math.Min(oldLow, low) : low; }
            if (b.High is { } high) { a.High = a.High is { } oldHigh ? Math.Max(oldHigh, high) : high; }
            Bounds(a, b.IndexLow, b.IndexHigh);
            if (b.Count is { } count) { a.Count = a.Count is { } oldCount ? Math.Max(oldCount, count) : count; }
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
                    // A thing at a record's address is its first field: what points to either points to the record.
                    TypeNode mine = a.Element.Find();
                    TypeNode theirs = b.Element.Find();
                    Unify(mine, theirs);
                    if (mine.Kind != TypeKind.Record && theirs.Find().Kind == TypeKind.Record)
                    {
                        a.Element = theirs.Find();
                    }
                }
            }

            if (b.Fields is not null)
            {
                a.Fields ??= [];
                foreach ((int offset, TypeNode field) in b.Fields)
                {
                    if (a.Fields.ContainsKey(offset))
                    {
                        Merge(a, offset, field);
                    }
                    else
                    {
                        a.Fields[offset] = field;
                    }
                }
            }

            if (b.Variants is not null)
            {
                foreach ((int offset, List<TypeNode> variants) in b.Variants)
                {
                    foreach (TypeNode variant in variants)
                    {
                        if (a.Fields?.ContainsKey(offset) == true)
                        {
                            Merge(a, offset, variant);
                        }
                        else
                        {
                            a.Fields ??= [];
                            a.Fields[offset] = variant;
                        }
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
        ///  Makes what two pointers point to one type; where it is a record, both point to the record, as a thing at a
        ///  record's address is its first field.
        /// </summary>
        /// <param name="first">One pointer.</param>
        /// <param name="second">The other.</param>
        public static void Targets(TypeNode first, TypeNode second)
        {
            TypeNode one = first.Target().Find();
            TypeNode other = second.Target().Find();
            Unify(one, other);
            TypeNode record = one.Find().Kind == TypeKind.Record ? one.Find() : other.Find();
            if (record.Kind != TypeKind.Record) { return; }

            first.Find().Element = record;
            second.Find().Element = record;
        }

        /// <summary>
        ///  Gets whether two types cannot be one, as two variants' fields at an offset cannot.
        /// </summary>
        /// <param name="first">One type.</param>
        /// <param name="second">The other.</param>
        /// <returns>Whether they differ.</returns>
        public static bool CannotBeOne(TypeNode first, TypeNode second) => Differ(first, second, depth: 3);

        /// <summary>
        ///  Puts a type at a record's word offset: into its field there, or a variant's, that it can be one with; or as
        ///  another variant's field.
        /// </summary>
        /// <param name="record">The record.</param>
        /// <param name="offset">The word offset.</param>
        /// <param name="type">The type.</param>
        /// <param name="evidence">
        ///  What a scalar's uses show it is, so that a boolean and an integer at one offset are two variants' fields.
        /// </param>
        public static void Place(TypeNode record, int offset, TypeNode type, Func<TypeNode, ScalarKind?> evidence) =>
            Merge(record.Find(), offset, type, evidence);

        // Puts a type at a record's word offset: into the field there, or a variant's, that it can be; or, where it is
        // a pointer and they integers or the other way round, as another variant's field.
        private static void Merge(TypeNode record, int offset, TypeNode type, Func<TypeNode, ScalarKind?>? evidence = null)
        {
            List<TypeNode> alternatives = record.Alternatives(offset);
            TypeNode root = type.Find();
            if (alternatives.Contains(root)) { return; }

            foreach (TypeNode alternative in alternatives)
            {
                // A record and a thing that is not one are two variants' fields, not the record's first.
                bool records = alternative.Find().Kind == TypeKind.Record || root.Kind == TypeKind.Record;
                bool known = alternative.Find().Kind != TypeKind.Unknown && root.Kind != TypeKind.Unknown;
                if (records && known && alternative.Find().Kind != root.Kind) { continue; }

                if (!Differ(alternative, root, depth: 3) && !Booleans(alternative, root, evidence))
                {
                    Unify(alternative, root);
                    return;
                }
            }

            record.Variants ??= [];
            if (!record.Variants.TryGetValue(offset, out List<TypeNode>? variants))
            {
                variants = [];
                record.Variants[offset] = variants;
            }

            variants.Add(root);
        }

        // Whether two scalars at one offset of a record are two variants' fields, as a boolean and an integer are.
        private static bool Booleans(TypeNode first, TypeNode second, Func<TypeNode, ScalarKind?>? evidence)
        {
            if (evidence is null || first.Find().Kind != TypeKind.Scalar || second.Find().Kind is not (TypeKind.Scalar or TypeKind.Unknown))
            {
                return false;
            }

            ScalarKind? one = evidence(first);
            ScalarKind? other = evidence(second);
            return one is not null && other is not null && one != other;
        }

        // Whether two types at one offset of a record are two variants' fields: they cannot be one, or are pointers to
        // records whose fields cannot be, as a variant's pointer to one record and another's to another; or one is a
        // packed array of more than a word's two bytes and the other a word.
        private static bool Differ(TypeNode first, TypeNode second, int depth)
        {
            TypeNode a = first.Find();
            TypeNode b = second.Find();
            if (a == b) { return false; }
            if (Conflicts(a, b) || Longer(a, b) || Longer(b, a)) { return true; }

            // An array and a scalar at one offset are two variants', as a constant's characters and another's number.
            if ((a.Kind, b.Kind) is (TypeKind.Array, TypeKind.Scalar) or (TypeKind.Scalar, TypeKind.Array))
            {
                return true;
            }

            // So are what code moves whole and a scalar, which the Compiler never moves.
            if ((a.Moved && b.Kind == TypeKind.Scalar) || (b.Moved && a.Kind == TypeKind.Scalar)) { return true; }

            // So are an array of bytes and one of words, or arrays whose elements cannot be one.
            if (a.Kind == TypeKind.Array && b.Kind == TypeKind.Array)
            {
                if (a.Bytes != b.Bytes) { return true; }
                bool elements = depth > 0 && a.Element is { } mine && b.Element is { } theirs && Differ(mine, theirs, depth - 1);
                if (elements) { return true; }
            }

            if (depth == 0) { return false; }

            if (a.Kind == TypeKind.Pointer && b.Kind == TypeKind.Pointer)
            {
                return a.Element is { } one && b.Element is { } other && Differ(one, other, depth - 1);
            }

            if (a.Kind == TypeKind.Record && b.Kind == TypeKind.Record && a.Fields is { } fields && b.Fields is { } others)
            {
                // A field inside another's words, as a word inside an identifier's name, is of another record.
                if (Inside(fields, others) || Inside(others, fields)) { return true; }

                foreach ((int offset, TypeNode field) in fields)
                {
                    if (others.TryGetValue(offset, out TypeNode? match) && Differ(field, match, depth - 1))
                    {
                        return true;
                    }
                }
            }

            return false;

            static bool Inside(SortedDictionary<int, TypeNode> wide, SortedDictionary<int, TypeNode> narrow)
            {
                foreach ((int offset, TypeNode field) in wide)
                {
                    int words = field.Find().Words;
                    if (words > 1 && narrow.Keys.Any(key => key > offset && key < offset + words)) { return true; }
                }

                return false;
            }

            static bool Longer(TypeNode array, TypeNode word)
            {
                bool bytes = array.Kind == TypeKind.Array && array.Bytes;
                return bytes && word.Kind == TypeKind.Scalar && (array.IndexHigh - array.IndexLow + 1 > 2 || array.Words > 1);
            }
        }

        /// <summary>
        ///  Whether two types cannot be one: they are of two kinds, neither unknown nor a record, but for an array and a
        ///  string, or an array of bytes and the word they make.
        /// </summary>
        /// <param name="first">One type.</param>
        /// <param name="second">The other.</param>
        /// <returns>Whether they are kept apart.</returns>
        public static bool Conflicts(TypeNode first, TypeNode second)
        {
            TypeNode one = first.Find();
            TypeNode other = second.Find();
            TypeKind a = one.Kind;
            TypeKind b = other.Kind;
            if (a == b || a is TypeKind.Unknown or TypeKind.Record || b is TypeKind.Unknown or TypeKind.Record)
            {
                return false;
            }

            bool strings = (a, b) is (TypeKind.Array, TypeKind.String) or (TypeKind.String, TypeKind.Array);
            bool bytes = (a == TypeKind.Array && one.Bytes && b == TypeKind.Scalar) || (b == TypeKind.Array && other.Bytes && a == TypeKind.Scalar);
            return !strings && !bytes;
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
                Count = Count,
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
