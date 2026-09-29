import {
    TranslationService,
    SupportedLanguage
} from "../services/translation.service";

const TRANSLATABLE_FIELDS = new Set([
    "name",
    "description",
    "title",
    "subtitle",
]);

/*
 * Maps a response key onto the content type it holds, so a missing
 * translation is recorded as "category" instead of everything
 * defaulting to "product".
 */
const TYPE_HINTS: Record<string, string> = {
    product: "product",
    products: "product",
    category: "category",
    categories: "category",
    subcategory: "category",
    subcategories: "category",
    campaign: "campaign",
    campaigns: "campaign",
    banner: "banner",
    banners: "banner",
};

const DEFAULT_TYPE = "content";

/*
 * Object shapes whose text must NEVER reach the translation system.
 *
 * The walker matches on field NAME alone, with no idea which entity it is
 * inside, so `user.name` and `deliveryBoy.name` on every order response were
 * being translated exactly like a product name — and, on a miss, written to
 * missing_translations, which the admin panel lists and exports to CSV. A
 * customer called Anaar or Sona is a live collision with catalogue vocabulary.
 *
 * Why a deny-list and not an allow-list of catalogue types: TypeORM returns real
 * entity instances for joined relations, so resolveType gives their class name
 * and they match here. Catalogue payloads go through mapProductPublic /
 * mapCategoryPublic, which spread into PLAIN objects — they carry no class name
 * and resolve to the inherited hint ("content"). Allow-listing "product" would
 * therefore have switched product translation off completely.
 */
const NEVER_TRANSLATE_TYPES = new Set([
    "user",
    "address",
    "order",
    "orderitem",
    "payment",
    "refund",
    "supportrequest",
    "riderprofile",
    "riderwallet",
    "ridercashdeposit",
]);

export class ResponseTranslator {

    /**
     * Values that are objects but are NOT containers we should walk into.
     *
     * A Date has no enumerable own keys, so rebuilding it produces {}
     * and destroys the timestamp before res.json() can serialise it.
     * Buffers, typed arrays, Maps and Sets degrade the same way.
     */
    private static isWalkable(value: any): boolean {

        if (value === null || typeof value !== "object")
            return false;

        if (value instanceof Date)
            return false;

        if (Buffer.isBuffer(value))
            return false;

        if (value instanceof RegExp)
            return false;

        if (value instanceof Map || value instanceof Set)
            return false;

        /*
         * Typed arrays / DataView.
         */
        if (ArrayBuffer.isView(value))
            return false;

        return true;
    }

    /**
     * Derive the content type for a value being walked.
     *
     * TypeORM entities carry their class name, which is the most
     * reliable signal. Plain objects fall back to the parent key.
     */
    private static resolveType(
        value: any,
        inheritedType: string
    ): string {

        const constructorName =
            value?.constructor?.name;

        if (
            constructorName &&
            constructorName !== "Object" &&
            constructorName !== "Array"
        ) {
            return constructorName.toLowerCase();
        }

        return inheritedType;
    }

    /**
     * Structural tell that an object describes a PERSON rather than catalogue
     * content.
     *
     * Needed because some person-shaped payloads are assembled by hand as plain
     * objects and so carry no class name for NEVER_TRANSLATE_TYPES to match —
     * AdminController.listRiders builds exactly that ({ riderId, name,
     * phoneNumber, ... }), and its rows would otherwise still be translated.
     *
     * No product, category or campaign carries a phone number; every
     * person-shaped row does.
     */
    private static describesAPerson(value: any): boolean {

        if (value === null || typeof value !== "object")
            return false;

        return "phoneNumber" in value || "phone_number" in value;
    }

    static translate(
        data: any,
        language: SupportedLanguage,
        type: string = DEFAULT_TYPE
    ): any {

        /*
         * English is the source language.
         *
         * Return the payload untouched so responses keep their
         * Date objects, Buffers and entity prototypes intact.
         */
        if (language === "en")
            return data;

        return this.walk(data, language, type);
    }

    private static walk(
        data: any,
        language: SupportedLanguage,
        type: string
    ): any {

        if (data == null)
            return data;

        /*
         * Array
         */
        if (Array.isArray(data)) {

            return data.map(item =>
                this.walk(item, language, type)
            );
        }

        /*
         * Anything object-like that we must not rebuild
         * (Date, Buffer, Map, ...) is passed straight through.
         */
        if (typeof data === "object" && !this.isWalkable(data))
            return data;

        /*
         * Object
         */
        if (typeof data === "object") {

            const currentType =
                this.resolveType(data, type);

            /*
             * PII guard. Nested objects are still walked — an order must keep
             * reaching its items and their products — but no string on THIS
             * object is handed to the translator.
             */
            const skipTranslation =
                NEVER_TRANSLATE_TYPES.has(currentType) ||
                this.describesAPerson(data);

            const translated: any = {};

            for (const key of Object.keys(data)) {

                const value = data[key];

                /*
                 * Only these fields are sent to the
                 * translation system.
                 */
                if (
                    TRANSLATABLE_FIELDS.has(key) &&
                    typeof value === "string" &&
                    !skipTranslation
                ) {

                    translated[key] =
                        TranslationService.translate(
                            value,
                            language,
                            currentType
                        );

                } else if (
                    value !== null &&
                    typeof value === "object"
                ) {

                    /*
                     * Recursively process nested objects
                     * and arrays, carrying down the content type
                     * implied by this key.
                     */
                    translated[key] =
                        this.walk(
                            value,
                            language,
                            TYPE_HINTS[key] ?? currentType
                        );

                } else {

                    /*
                     * IDs, prices, status, error messages,
                     * URLs, etc. remain untouched.
                     */
                    translated[key] = value;
                }
            }

            return translated;
        }

        /*
         * Primitive values remain unchanged.
         */
        return data;
    }
}
