import uuid

class LocalContext(object):
    """A class to simulate the Lambda context locally."""

    @property
    def invoked_function_arn(self):
        """Simulate the Lambda ARN that comes into the context object. """
        return 'arn:aws:lambda:ca-central-1:{0}:function:func-name'.format(123412341234)

    @property
    def aws_request_id(self):
        """Simulate the request guid that comes into the context object."""
        return str(uuid.uuid1())

    def __str__(self):
      return str((self.invoked_function_arn, self.aws_request_id))
