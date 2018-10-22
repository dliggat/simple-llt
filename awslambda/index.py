import logging
import os
import yaml
import pprint

from awslambda.utils.helpers import Helpers
from awslambda.utils.config import configuration


def handler(event, context):
    """Entry point for the Lambda function."""
    logger = Helpers.setup_logging(context.aws_request_id)
    config = configuration()

    pprint.pprint(config)

    # Used to differentiate local vs Lambda.
    if bool(os.getenv('IS_LOCAL')):
        logger.debug('$IS_LOCAL set; likely running in development')
    else:
        logger.debug('No $IS_LOCAL set; likely running in Lambda')
    return {'Success': True}


if __name__ == '__main__':
    from utils.localcontext import LocalContext
    handler(None, LocalContext())
