import { Request, Response, NextFunction } from "express";
import { ResponseTranslator } from "../Transport/responseTranslator";

export const responseMiddleware = (
    req: Request,
    res: Response,
    next: NextFunction
) => {

    const oldJson = res.json.bind(res);

    res.json = function (body: any) {

        const translated =
            ResponseTranslator.translate(
                body,
                req.language
            );

        return oldJson(translated);

    };

    next();

};