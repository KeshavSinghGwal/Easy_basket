import { Request, Response, NextFunction } from "express";

export type SupportedLanguage = "en" | "hi" | "pa";

declare global {
    namespace Express {
        interface Request {
            language: SupportedLanguage;
        }
    }
}

export const languageMiddleware = (
    req: Request,
    res: Response,
    next: NextFunction
) => {

    const language =
        (req.headers["accept-language"] as string || "en")
            .toLowerCase();

    if (language.startsWith("hi")) {
        req.language = "hi";
    } else if (language.startsWith("pa")) {
        req.language = "pa";
    } else {
        req.language = "en";
    }

    next();
};